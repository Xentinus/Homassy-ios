import Foundation
import Observation

@MainActor
@Observable
public final class StorePickerModel {
    public enum Tab: Hashable, Sendable { case recent, nearby }

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

    public var tab: Tab = .recent
    public var query = ""
    public var mapCenter: Coordinate?
    public private(set) var recent: [RecentStore] = []
    public private(set) var nearby: [StoreResult] = []
    public private(set) var searchResults: [StoreResult] = []
    public private(set) var isLoading = false
    public private(set) var message: Message?
    public private(set) var userCoordinate: Coordinate?

    /// Where to search: the user, else the map the user is looking at, else the last store used.
    public var searchCenter: Coordinate? { userCoordinate ?? mapCenter ?? recent.lazy.compactMap(\.coordinate).first }
    public var isShowingSearch: Bool { !searchResults.isEmpty }

    @ObservationIgnored private let search: any StoreSearching
    @ObservationIgnored private let locations: ShoppingLocationService
    @ObservationIgnored private let location: any LocationAuthorizing
    @ObservationIgnored private let space: Space
    @ObservationIgnored private var recentObjects: [UUID: ShoppingLocation] = [:]

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
        isLoading = true
        defer { isLoading = false }
        message = nil

        var access = location.access
        if access == .notDetermined { access = await location.requestWhenInUse() }
        if access == .authorized, let coordinate = await location.currentCoordinate() {
            userCoordinate = coordinate
        }
        guard let center = searchCenter else {
            nearby = []
            message = .needsLocation
            return
        }
        do {
            nearby = try await search.nearby(latitude: center.latitude, longitude: center.longitude,
                                             radiusMeters: Self.nearbyRadiusMeters)
            if nearby.isEmpty { message = .noResults }
        } catch {
            nearby = []
            message = .failed
        }
    }

    public func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            searchResults = []
            return
        }
        guard let center = searchCenter else {
            message = .needsLocation
            return
        }
        isLoading = true
        defer { isLoading = false }
        message = nil
        do {
            searchResults = try await search.search(text: text, latitude: center.latitude, longitude: center.longitude)
            if searchResults.isEmpty { message = .noResults }
        } catch {
            searchResults = []
            message = .failed
        }
    }

    public func clearSearch() {
        searchResults = []
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
