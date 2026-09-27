import Foundation
import Observation

/// The purchase sheet: how much was bought, whether the rest stays on the list, and whether it goes into
/// inventory (default on). With inventory, the amount is the lots, each with its own storage location and expiry
/// (P2-08a); the store comes from the store menu and the paid total is split across the lots. Undoable.
@MainActor
@Observable
public final class PurchaseFormModel {
    public let itemName: String
    public let listedQuantity: Decimal
    public let unit: MeasureUnit
    /// The amount while inventory is off.
    public var quantityText: String
    public var keepRemainder = true
    /// On by default; off, the item only leaves the list (user decision, 2026-09-25).
    public var addToInventory = true {
        didSet {
            guard addToInventory != oldValue else { return }
            if addToInventory {
                lots.setSingleQuantity(quantityText)
            } else if let total = lots.total {
                quantityText = Quantity.formatNumber(total, locale: locale)
            }
        }
    }
    public var priceText = ""
    public var currency: String
    public let lots: StockLotsModel
    public let store: StoreMenuModel
    public private(set) var errorMessage: String?

    @ObservationIgnored private let item: ShoppingListItem
    @ObservationIgnored private let shopping: ShoppingService
    @ObservationIgnored private let inventory: InventoryService
    @ObservationIgnored private let pending: PendingDeletions
    @ObservationIgnored private let locale: Locale

    public init(item: ShoppingListItem, shopping: ShoppingService, inventory: InventoryService,
                locations: ShoppingLocationService, pending: PendingDeletions, locale: Locale = .current) {
        self.item = item
        self.shopping = shopping
        self.inventory = inventory
        self.pending = pending
        self.locale = locale
        itemName = ShoppingService.displayName(of: item)
        listedQuantity = item.quantity
        unit = item.unit
        quantityText = Quantity.formatNumber(item.quantity, locale: locale)
        currency = inventory.defaultCurrency
        let space = item.shoppingList?.space
        var options: [PickerOption] = []
        if let space {
            let stored = (try? item.managedObjectContext?.fetchEntities(
                StorageLocation.self, where: NSPredicate(format: "space == %@", space),
                sortedBy: [NSSortDescriptor(key: "sortOrder", ascending: true)])) ?? []
            options = stored.map { PickerOption(id: $0.publicId, name: $0.name) }
        }
        let first = StockLot(
            quantityText: Quantity.formatNumber(item.quantity, locale: locale),
            storageLocationID: ShoppingPurchase.defaultStorageLocation(for: item.product, inventory: inventory)?.publicId)
        lots = StockLotsModel(first: first, storageOptions: options, allowsMultiple: true, locale: locale)
        store = StoreMenuModel(preset: item.shoppingLocation, product: item.product, space: space, locations: locations)
    }

    public var space: Space? { item.shoppingList?.space }
    /// The earliest expiry a lot can have.
    public var purchaseDate: Date { inventory.currentDate() }
    /// Store and price are asked whenever the purchase is recorded: always with inventory, and without it for
    /// product items (a custom item bought without inventory records nothing).
    public var recordsPurchase: Bool { addToInventory || item.product != nil }
    public var storeName: String? { store.name }
    /// Metres to the store when it came from the GPS suggestion.
    public var suggestedDistance: Double? { store.suggestedDistance }

    public var quantity: Decimal? {
        if addToInventory { return lots.total }
        guard let value = Quantity.parse(quantityText, locale: locale), value > 0 else { return nil }
        return value
    }

    /// The keep toggle only matters when less than listed was bought.
    public var showsKeepRemainder: Bool { quantity.map { $0 < listedQuantity } ?? false }

    public var remainderText: String? {
        guard let quantity, quantity < listedQuantity else { return nil }
        return Quantity.format(listedQuantity - quantity, unit: unit, locale: locale)
    }

    public var listedText: String { Quantity.format(listedQuantity, unit: unit, locale: locale) }
    public var canPurchase: Bool { quantity != nil }

    /// "450 Ft + 450 Ft" under the price when inventory gets two or more lots.
    public var priceSplitText: String? {
        guard addToInventory, lots.lotCount > 1, let text = priceText.nilIfBlank,
              let total = Quantity.parse(text, locale: locale), let amounts = lots.amounts else { return nil }
        return ProportionalSplit.text(total: total, weights: amounts,
                                      currency: currency.nilIfBlank ?? inventory.defaultCurrency, locale: locale)
    }

    public func setStore(_ location: ShoppingLocation?) { store.setStore(location) }
    public func applySuggestion(_ suggestion: StoreSuggestion) { store.applySuggestion(suggestion) }

    public func purchase() -> UndoableAction? {
        errorMessage = nil
        let lotDetails: [LotDetails]
        if addToInventory {
            guard let details = lots.details() else {
                errorMessage = coreLocalized("form.invalidQuantity")
                return nil
            }
            lotDetails = details
        } else {
            lotDetails = []
        }
        guard let quantity else {
            errorMessage = coreLocalized("form.invalidQuantity")
            return nil
        }
        var price: Decimal?
        if recordsPurchase, let text = priceText.nilIfBlank {
            guard let parsed = Quantity.parse(text, locale: locale) else {
                errorMessage = coreLocalized("form.invalidPrice")
                return nil
            }
            price = parsed
        }
        do {
            let shop = recordsPurchase ? try store.resolve() : nil
            let details = PurchaseDetails(quantity: quantity, storeID: shop?.publicId, keepRemainder: keepRemainder,
                                          price: price, currency: currency.nilIfBlank, lots: lotDetails,
                                          addToInventory: addToInventory)
            return try ShoppingPurchase.purchase(item, details: details, shopping: shopping, inventory: inventory,
                                                 pending: pending)
        } catch {
            errorMessage = FeatureError.message(for: error)
            return nil
        }
    }
}
