import Foundation
import Observation

/// The purchase sheet: how much was bought, whether the rest stays on the list, and whether it goes into
/// inventory (default on) with the store, price, expiry and storage location. Confirming is undoable.
@MainActor
@Observable
public final class PurchaseFormModel {
    public struct Option: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
    }

    public let itemName: String
    public let listedQuantity: Decimal
    public let unit: MeasureUnit
    public var quantityText: String
    public var keepRemainder = true
    /// On by default; off, the item only leaves the list (user decision, 2026-09-25).
    public var addToInventory = true
    public var priceText = ""
    public var currency: String
    public var hasExpiry = false
    public var expiresAt: Date
    public var storageLocationID: UUID?
    public private(set) var storageOptions: [Option] = []
    public private(set) var errorMessage: String?
    private var selection: StoreSelection

    @ObservationIgnored private let item: ShoppingListItem
    @ObservationIgnored private let shopping: ShoppingService
    @ObservationIgnored private let inventory: InventoryService
    @ObservationIgnored private let locations: ShoppingLocationService
    @ObservationIgnored private let pending: PendingDeletions
    @ObservationIgnored private let locale: Locale

    public init(item: ShoppingListItem, shopping: ShoppingService, inventory: InventoryService,
                locations: ShoppingLocationService, pending: PendingDeletions, locale: Locale = .current) {
        self.item = item
        self.shopping = shopping
        self.inventory = inventory
        self.locations = locations
        self.pending = pending
        self.locale = locale
        itemName = ShoppingService.displayName(of: item)
        listedQuantity = item.quantity
        unit = item.unit
        quantityText = Quantity.formatNumber(item.quantity, locale: locale)
        currency = inventory.defaultCurrency
        let today = inventory.calendar.startOfDay(for: inventory.currentDate())
        expiresAt = inventory.calendar.date(byAdding: .day, value: 7, to: today) ?? today
        selection = StoreSelection(preset: item.shoppingLocation)
        storageLocationID = ShoppingPurchase.defaultStorageLocation(for: item.product, inventory: inventory)?.publicId
        if let space = item.shoppingList?.space {
            let stored = (try? item.managedObjectContext?.fetchEntities(
                StorageLocation.self, where: NSPredicate(format: "space == %@", space),
                sortedBy: [NSSortDescriptor(key: "sortOrder", ascending: true)])) ?? []
            storageOptions = stored.map { Option(id: $0.publicId, name: $0.name) }
        }
    }

    public var space: Space? { item.shoppingList?.space }
    public var storeName: String? { selection.name }
    /// Metres to the store when it came from the GPS suggestion.
    public var suggestedDistance: Double? { selection.suggestedDistance }

    public var quantity: Decimal? {
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

    public func setStore(_ location: ShoppingLocation?) { selection.choose(location) }

    public func applySuggestion(_ suggestion: StoreSuggestion) {
        guard let space else { return }
        selection.apply(suggestion, locations: locations, space: space)
    }

    public func purchase() -> UndoableAction? {
        errorMessage = nil
        guard let quantity else {
            errorMessage = coreLocalized("form.invalidQuantity")
            return nil
        }
        var price: Decimal?
        if addToInventory, let text = priceText.nilIfBlank {
            guard let parsed = Quantity.parse(text, locale: locale) else {
                errorMessage = coreLocalized("form.invalidPrice")
                return nil
            }
            price = parsed
        }
        do {
            guard let space else { throw ServiceError.notFound }
            let store = addToInventory ? try selection.resolve(locations: locations, space: space) : nil
            let details = PurchaseDetails(quantity: quantity, storeID: store?.publicId, keepRemainder: keepRemainder,
                                          price: price, currency: currency.nilIfBlank,
                                          expiresAt: hasExpiry ? expiresAt : nil, storageLocationID: storageLocationID,
                                          addToInventory: addToInventory)
            return try ShoppingPurchase.purchase(item, details: details, shopping: shopping, inventory: inventory,
                                                 pending: pending)
        } catch {
            errorMessage = FeatureError.message(for: error)
            return nil
        }
    }
}
