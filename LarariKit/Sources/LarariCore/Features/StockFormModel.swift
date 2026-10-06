import CoreData
import Foundation
import Observation

/// A picker entry: a product or a storage location.
public struct PickerOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
}

/// LarariCore catalog string in the app's current language.
func coreLocalized(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: nil, table: "Localizable")
}

/// The add-stock and edit-stock sheet (P2-08a): the product, the shared unit, purchase date, store and paid
/// total, and the lots, each with its own amount, storage location and expiry. Editing has one lot.
@MainActor
@Observable
public final class StockFormModel {
    public enum Mode {
        case add(Space, productID: UUID?)
        case edit(InventoryItem)
    }

    public let targetSpace: Space?
    public private(set) var productID: UUID?
    public private(set) var productName: String?
    public var unit: MeasureUnit
    public let lots: StockLotsModel
    public let store: StoreMenuModel
    public var purchasedAt: Date
    /// The paid total for all lots.
    public var priceText: String
    public var currency: String
    public private(set) var priceError: String?
    public private(set) var errorMessage: String?

    @ObservationIgnored private let mode: Mode
    @ObservationIgnored private let inventory: InventoryService
    @ObservationIgnored private let products: ProductService
    @ObservationIgnored private let storage: StorageLocationService
    @ObservationIgnored private let locale: Locale

    public init(mode: Mode, inventory: InventoryService, products: ProductService, storage: StorageLocationService,
                locations: ShoppingLocationService, locale: Locale = .current) {
        self.mode = mode
        self.inventory = inventory
        self.products = products
        self.storage = storage
        self.locale = locale
        let calendar = inventory.calendar
        let today = calendar.startOfDay(for: inventory.currentDate())
        let space: Space? = switch mode {
        case .add(let target, _): target
        case .edit(let item): inventory.space(of: item)
        }
        targetSpace = space
        let storageOptions = ((space.flatMap { try? storage.locations(in: $0) }) ?? [])
            .map { PickerOption(id: $0.publicId, name: $0.name) }

        switch mode {
        case .add(let target, let id):
            let product = id.flatMap { try? products.product(publicId: $0) }.flatMap { $0.space == target ? $0 : nil }
            productID = product?.publicId
            productName = product?.name
            unit = product?.defaultUnit ?? .piece
            purchasedAt = today
            priceText = ""
            currency = inventory.defaultCurrency
            let first = StockLot(
                quantityText: Quantity.formatNumber(1, locale: locale),
                storageLocationID: ShoppingPurchase.defaultStorageLocation(for: product, inventory: inventory)?.publicId,
                expiresAt: calendar.date(byAdding: .day, value: 7, to: today) ?? today)
            lots = StockLotsModel(first: first, storageOptions: storageOptions, allowsMultiple: true, locale: locale)
            store = StoreMenuModel(preset: nil, product: product, space: space, locations: locations)
        case .edit(let item):
            productID = item.product?.publicId
            productName = item.product?.name
            unit = item.unit
            purchasedAt = item.purchasedAt ?? today
            priceText = item.price.map { Quantity.formatNumber($0, locale: locale) } ?? ""
            currency = item.currency ?? inventory.defaultCurrency
            let first = StockLot(quantityText: Quantity.formatNumber(item.quantity, locale: locale),
                                 storageLocationID: item.storageLocation?.publicId, expiresAt: item.expiresAt)
            lots = StockLotsModel(first: first, storageOptions: storageOptions, allowsMultiple: false, locale: locale)
            store = StoreMenuModel(preset: item.shoppingLocation, product: item.product, space: space,
                                   locations: locations)
        }
    }

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var hasProduct: Bool { productID != nil }
    public var canSave: Bool { productID != nil && lots.total != nil }

    /// Picked (or just created) in the product list: its unit, last storage location and stores apply. A single
    /// lot's location follows the product while it is still the previous product's default (none without one);
    /// a location the user picked by hand stays.
    public func setProduct(_ id: UUID) {
        guard !isEditing, let product = try? products.product(publicId: id), product.space == targetSpace else { return }
        let previous = productID.flatMap { try? products.product(publicId: $0) }
        let previousDefault = ShoppingPurchase.defaultStorageLocation(for: previous, inventory: inventory)?.publicId
        productID = id
        productName = product.name
        unit = product.defaultUnit
        if lots.lotCount == 1, lots.lots[0].storageLocationID == previousDefault {
            lots.lots[0].storageLocationID =
                ShoppingPurchase.defaultStorageLocation(for: product, inventory: inventory)?.publicId
        }
        store.setProduct(product)
    }

    /// The paid total split across two or more lots; nil for one lot or without a valid price.
    public var priceShares: [Decimal]? {
        guard lots.lotCount > 1, let total = parsedPrice, let amounts = lots.amounts else { return nil }
        return ProportionalSplit.split(total: total, weights: amounts)
    }

    /// "450 Ft + 450 Ft" for the price footer.
    public var priceSplitText: String? {
        guard lots.lotCount > 1, let total = parsedPrice, let amounts = lots.amounts else { return nil }
        return ProportionalSplit.text(total: total, weights: amounts,
                                      currency: currency.nilIfBlank ?? inventory.defaultCurrency, locale: locale)
    }

    public func save() -> [InventoryItem]? {
        priceError = nil
        errorMessage = nil
        guard let productID, let product = try? products.product(publicId: productID) else { return nil }
        guard let details = lots.details() else { return nil }
        var price: Decimal?
        if let text = priceText.nilIfBlank {
            guard let parsed = Quantity.parse(text, locale: locale) else {
                priceError = coreLocalized("form.invalidPrice")
                return nil
            }
            price = parsed
        }
        do {
            let shop = try store.resolve()
            switch mode {
            case .add:
                return try inventory.addStock(product: product, lots: details, unit: unit, purchasedAt: purchasedAt,
                                              totalPrice: price, currency: currency, shoppingLocation: shop)
            case .edit(let item):
                let lot = details[0]
                let location = try lot.storageLocationID.flatMap { try storage.location(publicId: $0) }
                try inventory.update(item, quantity: lot.quantity, unit: unit, expiresAt: lot.expiresAt,
                                     purchasedAt: purchasedAt, price: price, currency: currency,
                                     storageLocation: location, shoppingLocation: shop)
                return [item]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }

    private var parsedPrice: Decimal? { priceText.nilIfBlank.flatMap { Quantity.parse($0, locale: locale) } }
}
