import MapKit

/// What Apple Maps knows about a saved store (P2-08b, P2-08c): its short address and its category.
public struct StoreLookup: Sendable, Equatable {
    public let shortAddress: String?
    /// The `MKPointOfInterestCategory` raw value.
    public let category: String?

    public init(shortAddress: String?, category: String?) {
        self.shortAddress = shortAddress
        self.category = category
    }
}

/// Looks up a saved store by its Apple Maps identifier (P2-08b), for stores saved before addresses and categories
/// were cached.
@MainActor
public protocol StoreAddressResolving {
    func details(forMapItem identifier: String) async -> StoreLookup?
}

public struct MapKitStoreAddressResolver: StoreAddressResolving {
    public init() {}

    public func details(forMapItem identifier: String) async -> StoreLookup? {
        guard let id = MKMapItem.Identifier(rawValue: identifier),
              let item = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem else { return nil }
        return StoreLookup(shortAddress: item.address?.shortAddress, category: item.pointOfInterestCategory?.rawValue)
    }
}
