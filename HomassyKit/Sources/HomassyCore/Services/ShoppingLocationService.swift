import CoreData
import Foundation

/// Stores picked from Apple Maps (spec §6.7). There is no manual store management: a store exists
/// once someone picks it, matched by `mapItemIdentifier` inside the space.
@MainActor
public final class ShoppingLocationService {
    private let spaceStore: SpaceStore
    private let context: NSManagedObjectContext
    private let userRecordName: String
    private let canEditSpace: @MainActor (Space) -> Bool
    private let now: () -> Date
    /// Every Apple Maps pick, so its address is cached (P2-08b).
    public var onUpsert: (@MainActor (StoreResult) -> Void)?

    public init(spaceStore: SpaceStore, context: NSManagedObjectContext, userRecordName: String,
                canEdit: @escaping @MainActor (Space) -> Bool = { _ in true },
                now: @escaping () -> Date = { Date() }) {
        self.spaceStore = spaceStore
        self.context = context
        self.userRecordName = userRecordName
        self.canEditSpace = canEdit
        self.now = now
    }

    /// Returns the space's store for this map item, creating it the first time it is picked.
    @discardableResult
    public func upsert(_ result: StoreResult, in space: Space) throws -> ShoppingLocation {
        guard !space.isGone else { throw ServiceError.notFound }
        try ensureEditable(space)
        guard let name = result.name.nilIfBlank else { throw ServiceError.nameRequired }
        let date = now()

        if let existing = try fetch(NSPredicate(format: "space == %@ AND mapItemIdentifier == %@",
                                                space, result.mapItemIdentifier)).first {
            if existing.name != name || existing.latitude != result.latitude || existing.longitude != result.longitude {
                existing.name = name
                existing.latitude = result.latitude
                existing.longitude = result.longitude
                existing.stamp(by: userRecordName, now: date)
            }
            existing.lastUsedAt = date
            try save()
            onUpsert?(result)
            return existing
        }

        let location = spaceStore.insert(ShoppingLocation.self, in: space, by: userRecordName)
        location.space = space
        location.mapItemIdentifier = result.mapItemIdentifier
        location.name = name
        location.latitude = result.latitude
        location.longitude = result.longitude
        location.lastUsedAt = date
        location.stamp(by: userRecordName, now: date)
        try save()
        onUpsert?(result)
        return location
    }

    public func markUsed(_ location: ShoppingLocation) throws {
        try editableSpace(of: location)
        location.lastUsedAt = now()
        try save()
    }

    /// Most recently used first.
    public func recent(in space: Space, limit: Int = 10) throws -> [ShoppingLocation] {
        let sorted = try fetch(NSPredicate(format: "space == %@", space)).sorted { a, b in
            let left = a.lastUsedAt ?? .distantPast
            let right = b.lastUsedAt ?? .distantPast
            if left != right { return left > right }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }

    /// The store menu's entries (P2-08a): stores where `product` was bought, newest purchase first, then the
    /// space's other recent stores. No duplicates, no deleted stores, at most `limit`.
    public func recentStores(for product: Product?, in space: Space, limit: Int = 5) throws -> [ShoppingLocation] {
        var result: [ShoppingLocation] = []
        var seen = Set<NSManagedObjectID>()
        func add(_ store: ShoppingLocation?) {
            guard result.count < limit, let store, !store.isGone, store.space == space,
                  seen.insert(store.objectID).inserted else { return }
            result.append(store)
        }
        if let product, !product.isGone {
            let records = try context.fetchEntities(
                PurchaseRecord.self, where: NSPredicate(format: "product == %@ AND shoppingLocation != nil", product),
                sortedBy: [NSSortDescriptor(key: "purchasedAt", ascending: false)])
            records.forEach { add($0.shoppingLocation) }
        }
        try recent(in: space, limit: .max).forEach(add)
        return result
    }

    public func location(publicId: UUID, in space: Space) throws -> ShoppingLocation? {
        try fetch(NSPredicate(format: "space == %@ AND publicId == %@", space, publicId as NSUUID)).first
    }

    /// Items keep existing; they just lose their store.
    public func delete(_ location: ShoppingLocation) throws {
        try editableSpace(of: location)
        let date = now()
        let references = NSPredicate(format: "shoppingLocation == %@", location)
        for item in try context.fetchEntities(ShoppingListItem.self, where: references) {
            item.shoppingLocation = nil
            item.stamp(by: userRecordName, now: date)
        }
        for item in try context.fetchEntities(InventoryItem.self, where: references) {
            item.shoppingLocation = nil
            item.stamp(by: userRecordName, now: date)
        }
        context.delete(location)
        try save()
    }

    // MARK: Helpers

    private func fetch(_ predicate: NSPredicate) throws -> [ShoppingLocation] {
        try context.fetchEntities(ShoppingLocation.self, where: predicate)
    }

    private func editableSpace(of location: ShoppingLocation) throws {
        guard !location.isGone, let space = location.space else { throw ServiceError.notFound }
        try ensureEditable(space)
    }

    private func ensureEditable(_ space: Space) throws {
        guard canEditSpace(space) else { throw ServiceError.readOnlySpace }
    }

    private func save() throws {
        if context.hasChanges { try context.save() }
    }
}
