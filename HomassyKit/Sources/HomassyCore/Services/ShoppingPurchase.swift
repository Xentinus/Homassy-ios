import CoreData
import Foundation

/// What the user bought of one list item (the purchase sheet).
public struct PurchaseDetails: Sendable, Equatable {
    /// The bought amount; with lots it is their sum.
    public var quantity: Decimal
    /// `ShoppingLocation.publicId`; nil means no store.
    public var storeID: UUID?
    /// Keeps the rest on the list when less than listed was bought.
    public var keepRemainder: Bool
    public var price: Decimal?
    public var currency: String?
    /// One entry per stock item (P2-08a). Empty means one item of `quantity` without location or expiry.
    public var lots: [LotDetails]
    /// Off: the item only leaves the list (or shrinks to the remainder); nothing goes into inventory.
    public var addToInventory: Bool

    public init(quantity: Decimal, storeID: UUID? = nil, keepRemainder: Bool = true, price: Decimal? = nil,
                currency: String? = nil, lots: [LotDetails] = [], addToInventory: Bool = true) {
        self.quantity = quantity
        self.storeID = storeID
        self.keepRemainder = keepRemainder
        self.price = price
        self.currency = currency
        self.lots = lots
        self.addToInventory = addToInventory
    }

    /// What goes into inventory.
    var inventoryLots: [LotDetails] { lots.isEmpty ? [LotDetails(quantity: quantity)] : lots }
    /// What leaves the list.
    var boughtQuantity: Decimal {
        addToInventory && !lots.isEmpty ? lots.reduce(0) { $0 + $1.quantity } : quantity
    }
}

/// Buying a list item (the purchase sheet) puts it into inventory unless the user switches that off
/// (user decisions, 2026-09-25). The change is applied at once and saved on commit; the list item leaves
/// the list on commit unless a remainder stays.
@MainActor
public enum ShoppingPurchase {
    public static func purchase(_ item: ShoppingListItem, details: PurchaseDetails, shopping: ShoppingService,
                                inventory: InventoryService, pending: PendingDeletions) throws -> UndoableAction {
        guard !item.isGone, let space = item.shoppingList?.space, !space.isGone else { throw ServiceError.notFound }
        guard shopping.canEdit(space) else { throw ServiceError.readOnlySpace }
        guard details.boughtQuantity > 0 else { throw ServiceError.quantityMustBePositive }
        let purchasedAt = inventory.currentDate()
        let added = details.addToInventory
            ? try addStock(for: item, details: details, in: space, purchasedAt: purchasedAt,
                           shopping: shopping, inventory: inventory)
            : nil
        // Without inventory the purchase is still recorded for the price trend, when there is a product.
        let recordOnly = details.addToInventory
            ? nil
            : try recordOnly(for: item, details: details, in: space, purchasedAt: purchasedAt,
                             shopping: shopping, inventory: inventory)

        let previous = (quantity: item.quantity, updatedAt: item.updatedAt, updatedBy: item.updatedBy)
        let bought = details.boughtQuantity
        let keepsItem = details.keepRemainder && bought < item.quantity
        if keepsItem {
            item.quantity -= bought
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
                if let added {
                    for stock in added.stocks {
                        for event in stock.inventoryEventSet { inventory.discard(event) }
                        for record in stock.purchaseRecordSet { inventory.discard(record) }
                        inventory.discard(stock)
                    }
                    if added.createdProduct { inventory.discard(added.product) }
                }
                if let recordOnly { inventory.discard(recordOnly) }
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

    /// A list purchase that skips inventory: records where, how much and for how much when the item has a
    /// product (a custom item writes nothing, user decision 2026-09-25). Not saved.
    private static func recordOnly(for item: ShoppingListItem, details: PurchaseDetails, in space: Space,
                                   purchasedAt: Date, shopping: ShoppingService,
                                   inventory: InventoryService) throws -> PurchaseRecord? {
        guard let product = item.product, !product.isGone else { return nil }
        let store = try details.storeID.map { try entity(ShoppingLocation.self, $0, in: space, context: shopping.context) }
        return try inventory.recordPurchase(product: product, quantity: details.quantity, unit: item.unit,
                                            price: details.price, currency: details.currency, store: store,
                                            purchasedAt: purchasedAt, commit: false)
    }

    /// Validates and adds the stock, one item per lot (not saved). A product created for a custom item is
    /// removed again when adding fails.
    private static func addStock(for item: ShoppingListItem, details: PurchaseDetails, in space: Space,
                                 purchasedAt: Date, shopping: ShoppingService,
                                 inventory: InventoryService) throws -> (stocks: [InventoryItem], product: Product,
                                                                        createdProduct: Bool) {
        guard inventory.canEdit(space) else { throw ServiceError.readOnlySpace }
        // The lots are checked before a product is created: removing a new product again still leaves its
        // space changed, and a failed purchase must write nothing.
        _ = try inventory.validateLots(details.inventoryLots, purchasedAt: purchasedAt, in: space)
        let store = try details.storeID.map { try entity(ShoppingLocation.self, $0, in: space, context: shopping.context) }
        let (product, createdProduct) = try resolveProduct(for: item, userRecordName: shopping.userRecordName,
                                                           spaceStore: shopping.spaceStore)
        do {
            let stocks = try inventory.addStock(product: product, lots: details.inventoryLots, unit: item.unit,
                                                purchasedAt: purchasedAt, totalPrice: details.price,
                                                currency: details.currency, shoppingLocation: store, commit: false)
            return (stocks, product, createdProduct)
        } catch {
            if createdProduct { shopping.context.delete(product) }
            throw error
        }
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
