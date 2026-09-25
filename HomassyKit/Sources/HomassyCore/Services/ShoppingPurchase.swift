import CoreData
import Foundation

/// What the user bought of one list item (the purchase sheet; the checkbox uses defaults).
public struct PurchaseDetails: Sendable, Equatable {
    public var quantity: Decimal
    /// `ShoppingLocation.publicId`; nil means no store.
    public var storeID: UUID?
    /// Keeps the rest on the list when less than listed was bought.
    public var keepRemainder: Bool
    public var price: Decimal?
    public var currency: String?
    public var expiresAt: Date?
    /// `StorageLocation.publicId`; nil means no location.
    public var storageLocationID: UUID?

    public init(quantity: Decimal, storeID: UUID? = nil, keepRemainder: Bool = true, price: Decimal? = nil,
                currency: String? = nil, expiresAt: Date? = nil, storageLocationID: UUID? = nil) {
        self.quantity = quantity
        self.storeID = storeID
        self.keepRemainder = keepRemainder
        self.price = price
        self.currency = currency
        self.expiresAt = expiresAt
        self.storageLocationID = storageLocationID
    }
}

/// Buying a list item puts it straight into inventory (user decision, 2026-09-25). The change is applied
/// at once and saved on commit; the list item leaves the list on commit unless a remainder stays.
@MainActor
public enum ShoppingPurchase {
    public static func purchase(_ item: ShoppingListItem, details: PurchaseDetails, shopping: ShoppingService,
                                inventory: InventoryService, pending: PendingDeletions) throws -> UndoableAction {
        guard !item.isGone, let space = item.shoppingList?.space, !space.isGone else { throw ServiceError.notFound }
        guard shopping.canEdit(space), inventory.canEdit(space) else { throw ServiceError.readOnlySpace }
        guard details.quantity > 0 else { throw ServiceError.quantityMustBePositive }
        let purchasedAt = inventory.currentDate()
        if let expiresAt = details.expiresAt,
           inventory.calendar.startOfDay(for: expiresAt) < inventory.calendar.startOfDay(for: purchasedAt) {
            throw ServiceError.expiryBeforePurchase
        }
        let store = try details.storeID.map { try entity(ShoppingLocation.self, $0, in: space, context: shopping.context) }
        let location = try details.storageLocationID.map {
            try entity(StorageLocation.self, $0, in: space, context: shopping.context)
        }

        let (product, createdProduct) = try resolveProduct(for: item, userRecordName: shopping.userRecordName,
                                                           spaceStore: shopping.spaceStore)
        let stock: InventoryItem
        do {
            stock = try inventory.addStock(product: product, quantity: details.quantity, unit: item.unit,
                                           expiresAt: details.expiresAt, purchasedAt: purchasedAt,
                                           price: details.price, currency: details.currency,
                                           storageLocation: location, shoppingLocation: store, commit: false)
        } catch {
            if createdProduct { shopping.context.delete(product) }
            throw error
        }

        let previous = (quantity: item.quantity, updatedAt: item.updatedAt, updatedBy: item.updatedBy)
        let keepsItem = details.keepRemainder && details.quantity < item.quantity
        if keepsItem {
            item.quantity -= details.quantity
            item.stamp(by: shopping.userRecordName, now: purchasedAt)
        } else {
            pending.hide(item.publicId)
        }

        let id = item.publicId
        return UndoableAction(
            title: UndoTitle.purchased(ShoppingService.displayName(of: item)),
            kind: .purchase,
            entityIDs: [id],
            revert: {
                for event in stock.inventoryEventSet { inventory.discard(event) }
                inventory.discard(stock)
                if createdProduct { inventory.discard(product) }
                if !item.isGone {
                    item.quantity = previous.quantity
                    item.updatedAt = previous.updatedAt
                    item.updatedBy = previous.updatedBy
                }
                pending.restore(id)
                try? shopping.save()
            },
            commit: {
                defer { pending.restore(id) }
                if !keepsItem, !item.isGone { shopping.context.delete(item) }
                try shopping.save()
            })
    }

    /// The checkbox: the whole quantity at the item's store, no price or expiry, into the location
    /// the product was last stocked in.
    public static func quickPurchase(_ item: ShoppingListItem, shopping: ShoppingService,
                                     inventory: InventoryService, pending: PendingDeletions) throws -> UndoableAction {
        let details = PurchaseDetails(
            quantity: item.quantity,
            storeID: item.shoppingLocation?.publicId,
            keepRemainder: false,
            storageLocationID: defaultStorageLocation(for: item.product, inventory: inventory)?.publicId)
        return try purchase(item, details: details, shopping: shopping, inventory: inventory, pending: pending)
    }

    /// The location of the product's most recently added open stock item that has one.
    public static func defaultStorageLocation(for product: Product?, inventory: InventoryService) -> StorageLocation? {
        guard let product, !product.isGone else { return nil }
        let items = (try? inventory.items(for: product)) ?? []
        return items.filter { $0.storageLocation != nil }
            .max { $0.createdAt < $1.createdAt }?
            .storageLocation
    }

    /// The item's product; for a custom item, the space's product with the same name (case- and
    /// diacritic-insensitive), or a new one in the item's unit. Not saved.
    public static func resolveProduct(for item: ShoppingListItem, userRecordName: String,
                                      spaceStore: SpaceStore) throws -> (Product, created: Bool) {
        if let product = item.product, !product.isGone { return (product, false) }
        guard let space = item.shoppingList?.space, let context = item.managedObjectContext else {
            throw ServiceError.notFound
        }
        guard let name = item.customName?.nilIfBlank else { throw ServiceError.nameRequired }
        let match = try context.fetchEntities(
            Product.self, where: NSPredicate(format: "space == %@ AND name ==[cd] %@", space, name),
            sortedBy: [NSSortDescriptor(key: "createdAt", ascending: true)]).first
        if let match { return (match, false) }

        let product = spaceStore.insert(Product.self, in: space, by: userRecordName)
        product.space = space
        product.name = name
        product.defaultUnit = item.unit
        return (product, true)
    }

    private static func entity<T: HomassyEntity>(_ type: T.Type, _ id: UUID, in space: Space,
                                                 context: NSManagedObjectContext) throws -> T {
        let match = try context.fetchEntities(
            type, where: NSPredicate(format: "space == %@ AND publicId == %@", space, id as NSUUID)).first
        guard let match else { throw ServiceError.notFound }
        return match
    }
}
