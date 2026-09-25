import Foundation

/// The store the user is most likely standing in (spec: shopping purchase design).
public enum StoreSuggestion: Equatable, Sendable {
    /// A store the space already uses.
    case saved(id: UUID, name: String, distance: Double)
    /// An Apple Maps shop; picking it stores it through `ShoppingLocationService.upsert`.
    case place(StoreResult, distance: Double)

    public var name: String {
        switch self {
        case .saved(_, let name, _): name
        case .place(let result, _): result.name
        }
    }

    /// Metres from the user.
    public var distance: Double {
        switch self {
        case .saved(_, _, let distance), .place(_, let distance): distance
        }
    }
}

/// Suggests the nearest shop from GPS. A saved store of the space within the radius wins, because the
/// user has shopped there before; otherwise the nearest Apple Maps shop. Never asks for permission.
@MainActor
public final class NearestStoreSuggester {
    public static let radiusMeters: Double = 300

    private let search: any StoreSearching
    private let locations: ShoppingLocationService
    private let location: any LocationAuthorizing

    public init(search: any StoreSearching, locations: ShoppingLocationService, location: any LocationAuthorizing) {
        self.search = search
        self.locations = locations
        self.location = location
    }

    public func suggestion(in space: Space) async -> StoreSuggestion? {
        guard location.access == .authorized, let here = await location.currentCoordinate() else { return nil }

        let saved = ((try? locations.recent(in: space, limit: .max)) ?? []).compactMap { store -> StoreSuggestion? in
            guard let latitude = store.latitude, let longitude = store.longitude else { return nil }
            let point = StoreResult(mapItemIdentifier: store.mapItemIdentifier ?? "", name: store.name,
                                    latitude: latitude, longitude: longitude)
            let distance = point.distance(toLatitude: here.latitude, longitude: here.longitude)
            guard distance <= Self.radiusMeters else { return nil }
            return .saved(id: store.publicId, name: store.name, distance: distance)
        }
        if let nearest = saved.min(by: { $0.distance < $1.distance }) { return nearest }

        guard let results = try? await search.nearby(latitude: here.latitude, longitude: here.longitude,
                                                     radiusMeters: Self.radiusMeters) else { return nil }
        return results
            .map { StoreSuggestion.place($0, distance: $0.distance(toLatitude: here.latitude, longitude: here.longitude)) }
            .filter { $0.distance <= Self.radiusMeters }
            .min { $0.distance < $1.distance }
    }
}
