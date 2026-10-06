import CoreData
import CoreLocation
import Foundation
import Observation

/// Which store is which (P2-08b, option B): the subtitle "1,2 km · Sport u. 2–4., Budaörs" for pickers, and the
/// compact "Auchan · Budaörs" elsewhere. Addresses and categories come from `StoreAddressCache`; a missing address,
/// or a cached one without a category (P2-08c backfill), is looked up once per run. The distance uses the last
/// position, read only while location access is already granted.
@MainActor
@Observable
public final class StoreDirectory {
    public private(set) var coordinate: Coordinate?

    @ObservationIgnored private let context: NSManagedObjectContext
    @ObservationIgnored private let cache: StoreAddressCache
    @ObservationIgnored private let resolver: (any StoreAddressResolving)?
    @ObservationIgnored private let location: (any LocationAuthorizing)?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var requested: Set<String> = []
    /// Running address lookups; tests await them.
    @ObservationIgnored var lookups: [Task<Void, Never>] = []

    public init(context: NSManagedObjectContext, cache: StoreAddressCache, resolver: (any StoreAddressResolving)?,
                location: (any LocationAuthorizing)?, locale: Locale = .current) {
        self.context = context
        self.cache = cache
        self.resolver = resolver
        self.location = location
        self.locale = locale
    }

    /// Never asks for permission.
    public func refreshLocation() async {
        guard let location, location.access == .authorized,
              let current = await location.currentCoordinate() else { return }
        guard coordinate != current else { return }
        coordinate = current
    }

    /// A store picked from Apple Maps: its address is known right away.
    public func remember(_ result: StoreResult) {
        guard let address = StoreAddress(short: result.subtitle, category: result.category) else { return }
        cache.set(address, for: result.mapItemIdentifier)
    }

    public func address(ofStore id: UUID) -> StoreAddress? { store(id).flatMap(address(of:)) }

    public func address(of store: ShoppingLocation) -> StoreAddress? {
        guard let identifier = store.mapItemIdentifier else { return nil }
        let cached = cache.address(for: identifier)
        if cached?.category == nil { lookUp(identifier) }
        return cached
    }

    /// The store's Apple Maps category (`MKPointOfInterestCategory` raw value), once known.
    public func category(ofStore id: UUID) -> String? { address(ofStore: id)?.category }

    public func subtitle(ofStore id: UUID) -> String? { categoryAndSubtitle(ofStore: id).subtitle }

    /// Both for one row (the store picker's recent rows), from one store fetch.
    public func categoryAndSubtitle(ofStore id: UUID) -> (category: String?, subtitle: String?) {
        guard let store = store(id) else { return (nil, nil) }
        let address = address(of: store)
        return (address?.category,
                StoreLabel.subtitle(address: address, distance: distance(to: store), locale: locale))
    }

    public func compactName(ofStore id: UUID?) -> String? {
        guard let id, let store = store(id) else { return nil }
        let address = address(of: store)
        return StoreLabel.compact(name: store.name, address: address, useStreet: sharesLocality(store, address))
    }

    /// Metres from the last known position, for ordering the Shopping tab's store sections. Nil without a
    /// location, without store coordinates, or for an unknown store.
    public func distance(ofStore id: UUID) -> Double? { store(id).flatMap(distance(to:)) }

    private func distance(to store: ShoppingLocation) -> Double? {
        guard let coordinate, let latitude = store.latitude, let longitude = store.longitude else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    /// Another store of the space with the same name in the same locality.
    private func sharesLocality(_ store: ShoppingLocation, _ address: StoreAddress?) -> Bool {
        guard let locality = address?.locality, let space = store.space else { return false }
        let twins = (try? context.fetchEntities(
            ShoppingLocation.self,
            where: NSPredicate(format: "space == %@ AND name ==[cd] %@ AND self != %@", space, store.name, store))) ?? []
        return twins.contains { twin in
            guard let other = self.address(of: twin)?.locality else { return false }
            return other.compare(locality, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private func store(_ id: UUID) -> ShoppingLocation? {
        let match = try? context.fetchEntities(
            ShoppingLocation.self, where: NSPredicate(format: "publicId == %@", id as NSUUID)).first
        return match.flatMap { $0.isGone ? nil : $0 }
    }

    private func lookUp(_ identifier: String) {
        guard let resolver, requested.insert(identifier).inserted else { return }
        lookups.append(Task { [weak self] in
            guard let lookup = await resolver.details(forMapItem: identifier), let self else { return }
            // A backfill without an address keeps the cached one; either way the category is saved.
            let cached = cache.address(for: identifier)
            guard let address = StoreAddress(short: lookup.shortAddress ?? cached?.short,
                                             category: lookup.category ?? cached?.category) else { return }
            cache.set(address, for: identifier)
        })
    }
}
