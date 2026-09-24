import CoreData
import Foundation
import Observation

/// A picker entry: a product or a storage location.
public struct PickerOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
}

/// HomassyCore catalog string in the app's current language.
func coreLocalized(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: nil, table: "Localizable")
}

/// The add-stock and edit-stock sheet.
@MainActor
@Observable
public final class StockFormModel {
    public enum Mode {
        case add(Space, productID: UUID?)
        case edit(InventoryItem)
    }

    public let targetSpace: Space?
    public private(set) var productOptions: [PickerOption] = []
    public private(set) var locationOptions: [PickerOption] = []
    public var productID: UUID? {
        didSet {
            guard !isEditing, productID != oldValue, let id = productID, let product = productObjects[id] else { return }
            unit = product.defaultUnit
        }
    }
    public var quantityText: String
    public var unit: MeasureUnit
    public var hasExpiry: Bool
    public var expiresAt: Date
    public var purchasedAt: Date
    public var locationID: UUID?
    public var priceText: String
    public var currency: String
    public private(set) var quantityError: String?
    public private(set) var priceError: String?
    public private(set) var errorMessage: String?

    private let mode: Mode
    private let inventory: InventoryService
    private let products: ProductService
    private let storage: StorageLocationService
    private let locale: Locale
    private var productObjects: [UUID: Product] = [:]
    private var locationObjects: [UUID: StorageLocation] = [:]

    public init(mode: Mode, inventory: InventoryService, products: ProductService, storage: StorageLocationService,
                locale: Locale = .current) {
        self.mode = mode
        self.inventory = inventory
        self.products = products
        self.storage = storage
        self.locale = locale
        let calendar = inventory.calendar
        let today = calendar.startOfDay(for: inventory.currentDate())

        switch mode {
        case .add(let space, _):
            targetSpace = space
            quantityText = Quantity.formatNumber(1, locale: locale)
            unit = .piece
            hasExpiry = true
            expiresAt = calendar.date(byAdding: .day, value: 7, to: today) ?? today
            purchasedAt = today
            locationID = nil
            priceText = ""
            currency = inventory.defaultCurrency
        case .edit(let item):
            targetSpace = inventory.space(of: item)
            quantityText = Quantity.formatNumber(item.quantity, locale: locale)
            unit = item.unit
            hasExpiry = item.expiresAt != nil
            expiresAt = item.expiresAt ?? calendar.date(byAdding: .day, value: 7, to: today) ?? today
            purchasedAt = item.purchasedAt ?? today
            locationID = item.storageLocation?.publicId
            priceText = item.price.map { Quantity.formatNumber($0, locale: locale) } ?? ""
            currency = item.currency ?? inventory.defaultCurrency
        }
        refreshOptions()
        // Property observers do not run inside init, so the default unit is applied here explicitly.
        switch mode {
        case .add(_, let productID):
            self.productID = productID
            if let productID, let product = productObjects[productID] { unit = product.defaultUnit }
        case .edit(let item):
            self.productID = item.product?.publicId
        }
    }

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var canSave: Bool { productID != nil }

    public func productCreated(_ product: Product) {
        refreshOptions()
        productID = product.publicId
    }

    public func save() -> InventoryItem? {
        quantityError = nil
        priceError = nil
        errorMessage = nil
        guard let productID, let product = productObjects[productID] else { return nil }
        guard let quantity = Quantity.parse(quantityText, locale: locale), quantity > 0 else {
            quantityError = coreLocalized("form.invalidQuantity")
            return nil
        }
        var price: Decimal?
        if let text = priceText.nilIfBlank {
            guard let parsed = Quantity.parse(text, locale: locale) else {
                priceError = coreLocalized("form.invalidPrice")
                return nil
            }
            price = parsed
        }
        let location = locationID.flatMap { locationObjects[$0] }
        let expiry = hasExpiry ? expiresAt : nil
        do {
            switch mode {
            case .add:
                return try inventory.addStock(product: product, quantity: quantity, unit: unit, expiresAt: expiry,
                                              purchasedAt: purchasedAt, price: price, currency: currency,
                                              storageLocation: location, shoppingLocation: nil)
            case .edit(let item):
                try inventory.update(item, quantity: quantity, unit: unit, expiresAt: expiry, purchasedAt: purchasedAt,
                                     price: price, currency: currency, storageLocation: location)
                return item
            }
        } catch ServiceError.quantityMustBePositive {
            quantityError = ServiceError.quantityMustBePositive.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }

    private func refreshOptions() {
        guard let space = targetSpace else { return }
        let allProducts = (try? products.products(in: space)) ?? []
        productObjects = Dictionary(allProducts.map { ($0.publicId, $0) }, uniquingKeysWith: { first, _ in first })
        productOptions = allProducts.map { PickerOption(id: $0.publicId, name: $0.name) }
        let allLocations = (try? storage.locations(in: space)) ?? []
        locationObjects = Dictionary(allLocations.map { ($0.publicId, $0) }, uniquingKeysWith: { first, _ in first })
        locationOptions = allLocations.map { PickerOption(id: $0.publicId, name: $0.name) }
    }
}
