import MapKit

/// Looks up a saved store's short address by its Apple Maps identifier (P2-08b), for stores saved before
/// addresses were cached.
@MainActor
public protocol StoreAddressResolving {
    func shortAddress(forMapItem identifier: String) async -> String?
}

public struct MapKitStoreAddressResolver: StoreAddressResolving {
    public init() {}

    public func shortAddress(forMapItem identifier: String) async -> String? {
        guard let id = MKMapItem.Identifier(rawValue: identifier),
              let item = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem else { return nil }
        return item.address?.shortAddress
    }
}
