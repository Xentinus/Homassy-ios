import Foundation
import Observation

@MainActor
@Observable
public final class StorePickerModel {
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

    public var query = ""
    public var mapCenter: Coordinate?
    public private(set) var recent: [RecentStore] = []
    public private(set) var nearby: [StoreResult] = []
    public private(set) var searchResults: [StoreResult] = []
    /// Addresses and places matching the query; picking one moves the map there.
    public private(set) var placeResults: [PlaceResult] = []
    /// A request to move the map. Each request has its own id, so asking for the same place again (after a pan)
    /// still moves the camera.
    public struct CameraTarget: Equatable, Sendable {
        public let id = UUID()
        public let coordinate: Coordinate
    }

    /// Where the view should move the map (the user's position, the fallback centre, or a place from the search).
    public private(set) var cameraTarget: CameraTarget?
    /// The query the shown results belong to; while the field differs from it, the view offers suggestions.
    public private(set) var submittedQuery: String?
    public var isLoading: Bool { isLoadingNearby || isSearching }
    public private(set) var message: Message?
    public private(set) var userCoordinate: Coordinate?
    /// A shop tapped on the map (a result marker or any Apple Maps place), waiting for "Choose".
    public private(set) var selectedPlace: StoreResult?

    public static let addressRadiusMeters: Double = 150
    /// The address the search jumped to; distances are measured from it (P2-08c).
    public private(set) var addressFocus: PlaceResult?

    /// Where to search: the map the user is looking at, else the user, else the last store used.
    public var searchCenter: Coordinate? { mapCenter ?? userCoordinate ?? recent.lazy.compactMap(\.coordinate).first }
    public var isShowingSearch: Bool { !searchResults.isEmpty || !placeResults.isEmpty || addressFocus != nil }

    /// Where distances in the list are measured from: the focused address, the user, or the map centre.
    public var distanceOrigin: Coordinate? { addressFocus?.coordinate ?? userCoordinate ?? mapCenter }

    public func distanceText(for result: StoreResult) -> String? {
        guard let origin = distanceOrigin else { return nil }
        return StoreLabel.distanceText(result.distance(toLatitude: origin.latitude, longitude: origin.longitude))
    }

    @ObservationIgnored private let search: any StoreSearching
    @ObservationIgnored private let locations: ShoppingLocationService
    @ObservationIgnored private let location: any LocationAuthorizing
    @ObservationIgnored private let space: Space
    @ObservationIgnored private var recentObjects: [UUID: ShoppingLocation] = [:]
    /// Bumped by every new search, focus and clear; a search whose generation is no longer current drops its
    /// results, so a late answer never lands after a clear or over a newer search.
    @ObservationIgnored private var searchGeneration = 0
    private var isLoadingNearby = false
    /// The current search is running; a stale search never clears it.
    private var isSearching = false

    public init(search: any StoreSearching, locations: ShoppingLocationService,
                location: any LocationAuthorizing, space: Space) {
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
        isLoadingNearby = true
        defer { isLoadingNearby = false }
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
        cameraTarget = CameraTarget(coordinate: center)
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

    /// Jumps to an address and lists every business around it, nearest to the address first.
    public func focus(on place: PlaceResult) async {
        let generation = beginSearch()
        defer { endSearch(generation) }
        await applyFocus(place, generation: generation)
    }

    /// The focus itself, for a search that already owns `generation` (so it is not bumped again).
    private func applyFocus(_ place: PlaceResult, generation: Int) async {
        addressFocus = place
        placeResults = []
        cameraTarget = CameraTarget(coordinate: place.coordinate)
        mapCenter = place.coordinate
        message = nil
        do {
            let found = try await search.around(latitude: place.coordinate.latitude,
                                                longitude: place.coordinate.longitude,
                                                radiusMeters: Self.addressRadiusMeters)
            guard generation == searchGeneration else { return }
            searchResults = MapKitStoreSearch.rank(found, latitude: place.coordinate.latitude,
                                                   longitude: place.coordinate.longitude)
            if searchResults.isEmpty { message = .noResults }
        } catch {
            guard generation == searchGeneration else { return }
            searchResults = []
            message = .failed
        }
    }

    public func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            clearSearch()
            return
        }
        let generation = beginSearch()
        defer { endSearch(generation) }
        guard let center = searchCenter else {
            message = .needsLocation
            return
        }
        addressFocus = nil

        if StoreQuery.isAddress(text) {
            let placeResult = await Self.result { try await self.search.places(text: text, latitude: center.latitude,
                                                                                longitude: center.longitude) }
            guard generation == searchGeneration else { return }
            let places = (try? placeResult.get()) ?? []
            if let first = places.first {
                await applyFocus(first, generation: generation)   // clears `message` itself
                guard generation == searchGeneration else { return }
                placeResults = Array(places.dropFirst())
                return
            }
            message = nil
            let shopResult = await Self.result { try await self.search.search(text: text, latitude: center.latitude,
                                                                               longitude: center.longitude) }
            guard generation == searchGeneration else { return }
            finishBusinessSearch(shopResult: shopResult, placeResult: placeResult, center: center)
            return
        }

        message = nil
        async let shops = Self.result { try await self.search.search(text: text, latitude: center.latitude,
                                                                     longitude: center.longitude) }
        async let places = Self.result { try await self.search.places(text: text, latitude: center.latitude,
                                                                      longitude: center.longitude) }
        let (shopResult, placeResult) = await (shops, places)
        guard generation == searchGeneration else { return }
        finishBusinessSearch(shopResult: shopResult, placeResult: placeResult, center: center)
    }

    /// Starts a search that supersedes every earlier one.
    private func beginSearch() -> Int {
        searchGeneration += 1
        submittedQuery = query
        isSearching = true
        return searchGeneration
    }

    /// Only the current search turns the spinner off.
    private func endSearch(_ generation: Int) {
        if generation == searchGeneration { isSearching = false }
    }

    /// Shared by the plain business search and the address-with-no-match fallback (P2-08c fix round 1).
    private func finishBusinessSearch(shopResult: Result<[StoreResult], any Error>,
                                       placeResult: Result<[PlaceResult], any Error>, center: Coordinate) {
        placeResults = (try? placeResult.get()) ?? []
        let origin = userCoordinate ?? center
        searchResults = MapKitStoreSearch.rank((try? shopResult.get()) ?? [], latitude: origin.latitude,
                                               longitude: origin.longitude)
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
        searchGeneration += 1   // drops any search still running
        isSearching = false
        searchResults = []
        placeResults = []
        addressFocus = nil
        submittedQuery = nil
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
