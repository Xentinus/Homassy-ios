import Foundation
import Observation

@MainActor
@Observable
public final class StorePickerModel {
    public enum Tab: Hashable, Sendable, Identifiable {
        case recent, nearby
        public var id: Self { self }
    }

    public enum Message: Equatable, Sendable {
        case needsLocation, noResults, failed

        public var text: String {
            switch self {
            case .needsLocation: String(localized: "store.message.needsLocation", bundle: .module)
            case .noResults: String(localized: "store.message.noResults", bundle: .module)
            case .failed: String(localized: "store.message.failed", bundle: .module)
            }
        }
    }

    public struct RecentStore: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let coordinate: Coordinate?
    }

    public static let nearbyRadiusMeters: Double = 2_000
    /// The area search follows the visible map, within these bounds.
    public static let areaRadiusRange: ClosedRange<Double> = 250...5_000

    public var tab: Tab = .recent
    public var query = ""
    public var mapCenter: Coordinate?
    public private(set) var recent: [RecentStore] = []
    public private(set) var nearby: [StoreResult] = []
    public private(set) var searchResults: [StoreResult] = []
    /// Addresses and places matching the query; picking one moves the map there.
    public private(set) var placeResults: [PlaceResult] = []
    /// Where the view should move the map (the user's position, or a place from the search).
    public private(set) var cameraTarget: Coordinate?
    public private(set) var isLoading = false
    public private(set) var message: Message?
    public private(set) var userCoordinate: Coordinate?
    /// A shop tapped on the map (a result marker or any Apple Maps place), waiting for "Choose".
    public private(set) var selectedPlace: StoreResult?

    /// Where to search: the map the user is looking at, else the user, else the last store used.
    public var searchCenter: Coordinate? { mapCenter ?? userCoordinate ?? recent.lazy.compactMap(\.coordinate).first }
    public var isShowingSearch: Bool { !searchResults.isEmpty || !placeResults.isEmpty }

    @ObservationIgnored private let search: any StoreSearching
    @ObservationIgnored private let locations: ShoppingLocationService
    @ObservationIgnored private let location: any LocationAuthorizing
    @ObservationIgnored private let space: Space
    @ObservationIgnored private var recentObjects: [UUID: ShoppingLocation] = [:]

    public init(search: any StoreSearching, locations: ShoppingLocationService,
                location: any LocationAuthorizing, space: Space, initialTab: Tab = .recent) {
        self.tab = initialTab
        self.search = search
        self.locations = locations
        self.location = location
        self.space = space
    }

    public func loadRecent() {
        let stores = (try? locations.recent(in: space)) ?? []
        recentObjects = Dictionary(stores.map { ($0.publicId, $0) }, uniquingKeysWith: { first, _ in first })
        recent = stores.map { store in
            // latitude/longitude are Double? (README entity table); a store without both has no coordinate.
            let coordinate = store.latitude.flatMap { lat in
                store.longitude.map { Coordinate(latitude: lat, longitude: $0) }
            }
            return RecentStore(id: store.publicId, name: store.name, coordinate: coordinate)
        }
    }

    public func loadNearby() async {
        isLoading = true
        defer { isLoading = false }
        message = nil

        var access = location.access
        if access == .notDetermined { access = await location.requestWhenInUse() }
        var fresh: Coordinate?
        if access == .authorized, let coordinate = await location.currentCoordinate() {
            userCoordinate = coordinate
            fresh = coordinate
        }
        guard let center = fresh ?? searchCenter else {
            nearby = []
            message = .needsLocation
            return
        }
        if fresh != nil { cameraTarget = center }
        do {
            nearby = try await search.nearby(latitude: center.latitude, longitude: center.longitude,
                                             radiusMeters: Self.nearbyRadiusMeters)
            if nearby.isEmpty { message = .noResults }
        } catch {
            nearby = []
            message = .failed
        }
    }

    /// The map was moved: shops in the visible area (radius clamped to `areaRadiusRange`).
    public func searchArea(center: Coordinate, radiusMeters: Double) async {
        mapCenter = center
        let radius = min(max(radiusMeters, Self.areaRadiusRange.lowerBound), Self.areaRadiusRange.upperBound)
        do {
            let found = try await search.nearby(latitude: center.latitude, longitude: center.longitude,
                                                radiusMeters: radius)
            guard !Task.isCancelled else { return }
            nearby = found
            message = found.isEmpty ? .noResults : nil
        } catch {
            guard !Task.isCancelled else { return }
            message = .failed
        }
    }

    /// Moves the map to a place from the search and shows the shops around it.
    public func goTo(_ place: PlaceResult) async {
        tab = .nearby
        clearSearch()
        cameraTarget = place.coordinate
        await searchArea(center: place.coordinate, radiusMeters: Self.nearbyRadiusMeters)
    }

    public func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            searchResults = []
            placeResults = []
            return
        }
        guard let center = searchCenter else {
            message = .needsLocation
            return
        }
        isLoading = true
        defer { isLoading = false }
        message = nil
        async let shops = Self.result { try await self.search.search(text: text, latitude: center.latitude,
                                                                     longitude: center.longitude) }
        async let places = Self.result { try await self.search.places(text: text, latitude: center.latitude,
                                                                      longitude: center.longitude) }
        let (shopResult, placeResult) = await (shops, places)
        searchResults = (try? shopResult.get()) ?? []
        placeResults = (try? placeResult.get()) ?? []
        if case .failure = shopResult, case .failure = placeResult {
            message = .failed
        } else if searchResults.isEmpty && placeResults.isEmpty {
            message = .noResults
        }
    }

    private static func result<T: Sendable>(_ work: () async throws -> T) async -> Result<T, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    public func clearSearch() {
        searchResults = []
        placeResults = []
        if message == .noResults { message = nil }
    }

    public func pick(_ result: StoreResult) -> ShoppingLocation? {
        do {
            let stored = try locations.upsert(result, in: space)
            loadRecent()
            return stored
        } catch {
            message = .failed
            return nil
        }
    }

    public func select(_ place: StoreResult) { selectedPlace = place }

    public func clearSelection() { selectedPlace = nil }

    /// Stores the place tapped on the map and clears the selection.
    public func pickSelected() -> ShoppingLocation? {
        guard let place = selectedPlace else { return nil }
        let stored = pick(place)
        if stored != nil { selectedPlace = nil }
        return stored
    }

    public func pickRecent(_ id: UUID) -> ShoppingLocation? {
        guard let store = recentObjects[id] else { return nil }
        try? locations.markUsed(store)
        loadRecent()
        return store
    }

    public func deleteRecent(_ id: UUID) {
        guard let store = recentObjects[id] else { return }
        try? locations.delete(store)
        loadRecent()
    }
}
