import CoreData
import Foundation
import Observation

/// The header card of the product detail.
public struct ProductFields: Equatable, Sendable {
    public let name: String
    public let brand: String?
    public let category: String?
    public let barcode: String?
    public let unitName: String
    public let isEatable: Bool
    public let isFavorite: Bool
    public let notes: String?
    public let image: Data?
}

/// One stock item card inside a storage-location group.
public struct StockItemCard: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let quantity: Decimal
    public let unit: MeasureUnit
    public let quantityText: String
    public let purchasedAt: Date?
    public let expiresAt: Date?
    public let level: ExpirationLevel
    public let expiryText: String?
}

/// The stock of one storage location ("Pantry 2 pcs"). `name` is nil for items without a location.
public struct StockGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let totalText: String
    public let items: [StockItemCard]
}

/// One purchase with a price, for the price trend.
public struct PriceRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date?
    public let storeName: String?
    public let priceText: String
    public let quantityText: String
}

/// One `InventoryEvent`, with who did it. `actorName` is nil for the current user and for unknown members.
public struct HistoryRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: InventoryEventKind
    public let quantityText: String
    public let fromLocation: String?
    public let toLocation: String?
    public let occurredAt: Date?
    public let actorName: String?
    public let actorSeed: String
    public let isCurrentUser: Bool
}

/// A move target: a storage location, or `id == nil` for "no location".
public struct LocationOption: Identifiable, Equatable, Sendable {
    public let id: UUID?
    public let name: String?
}

/// The product detail (README "Product detail layout"): header, stock by location with consume, move and
/// delete, price trend and history. Every action returns an `UndoableAction` for the toast.
@MainActor
@Observable
public final class ProductDetailModel {
    public let product: Product
    public private(set) var fields: ProductFields?
    /// Every open item by location; `stockGroups` hides the ones whose delete is in its undo window.
    private var allGroups: [StockGroup] = []
    public private(set) var priceHistory: [PriceRow] = []
    public private(set) var history: [HistoryRow] = []
    public private(set) var errorMessage: String?

    private let products: ProductService
    private let inventory: InventoryService
    private let storageLocations: StorageLocationService
    private let pending: PendingDeletions
    private let userRecordName: String
    private let locale: Locale
    private let spaces: @MainActor () -> [Space]
    private var openItems: [InventoryItem] = []

    /// `spaces` lists every space the user belongs to; transfer targets are the other editable ones.
    public init(product: Product, products: ProductService, inventory: InventoryService,
                storageLocations: StorageLocationService, pending: PendingDeletions, userRecordName: String,
                locale: Locale = .current, spaces: @escaping @MainActor () -> [Space] = { [] }) {
        self.spaces = spaces
        self.product = product
        self.products = products
        self.inventory = inventory
        self.storageLocations = storageLocations
        self.pending = pending
        self.userRecordName = userRecordName
        self.locale = locale
    }

    public var canEdit: Bool { product.space.map(products.canEdit) ?? false }

    /// The stock by storage location, without items whose delete is still in its undo window.
    public var stockGroups: [StockGroup] {
        allGroups.compactMap { group in
            let items = group.items.filter { !pending.contains($0.id) }
            guard !items.isEmpty else { return nil }
            let total = StockSummary.text(for: items.map { ($0.quantity, $0.unit) }, locale: locale) ?? ""
            return StockGroup(id: group.id, name: group.name, totalText: total, items: items)
        }
    }

    /// Open stock items shown.
    public var stockCount: Int { stockGroups.reduce(0) { $0 + $1.items.count } }

    public func reload() {
        guard !product.isGone, let space = product.space else {
            fields = nil
            allGroups = []
            priceHistory = []
            history = []
            openItems = []
            return
        }
        fields = ProductFields(name: product.name, brand: product.brand, category: product.category,
                               barcode: product.barcode, unitName: product.defaultUnit.name(for: 1, locale: locale),
                               isEatable: product.isEatable, isFavorite: product.isFavorite,
                               notes: product.notes, image: product.image)
        do {
            openItems = try inventory.items(for: product)
            allGroups = try groups(in: space)
            priceHistory = try prices()
            history = try inventory.events(for: product).map(row)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Actions

    public func toggleFavorite() {
        run { try products.setFavorite(product, !product.isFavorite) }
        reload()
    }

    public func consume(_ itemID: UUID, amount: Decimal) -> UndoableAction? {
        action { try InventoryActions.consume(try item(itemID), quantity: amount, service: inventory) }
    }

    /// Moves `amount` of the item; less than all of it splits the item. `locationID == nil` means no location.
    public func move(_ itemID: UUID, amount: Decimal, to locationID: UUID?) -> UndoableAction? {
        action {
            let target = try locationID.map { id -> StorageLocation in
                guard let location = try storageLocations.location(publicId: id) else { throw ServiceError.notFound }
                return location
            }
            return try InventoryActions.move(try item(itemID), quantity: amount, to: target, service: inventory)
        }
    }

    public func deleteItem(_ itemID: UUID) -> UndoableAction? {
        action { try InventoryActions.delete(try item(itemID), service: inventory, pending: pending) }
    }

    public func deleteProduct() -> UndoableAction? {
        action { try products.deletion(of: product, pending: pending) }
    }

    /// Every storage location of the product's space except the item's own, matching `query`,
    /// followed by "no location" when the item has one.
    public func moveTargets(for itemID: UUID, matching query: String) -> [LocationOption] {
        guard let item = try? item(itemID), let space = product.space else { return [] }
        let all = (try? storageLocations.locations(in: space)) ?? []
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = all
            .filter { $0 != item.storageLocation }
            .filter { text.isEmpty || $0.name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .map { LocationOption(id: $0.publicId, name: $0.name) }
        if item.storageLocation != nil, text.isEmpty { options.append(LocationOption(id: nil, name: nil)) }
        return options
    }

    /// The amount sheet for consume or move: starts with the full remaining amount, capped at it.
    public func amountForm(for itemID: UUID) -> AmountFormModel? {
        guard let item = try? item(itemID), !item.isFullyConsumed else { return nil }
        return AmountFormModel(maximum: item.quantity, unit: item.unit, locale: locale)
    }

    /// The edit-stock sheet for one item.
    public func editForm(for itemID: UUID) -> StockFormModel? {
        guard let item = try? item(itemID) else { return nil }
        return StockFormModel(mode: .edit(item), inventory: inventory, products: products, storage: storageLocations,
                              locale: locale)
    }

    /// Other spaces the item can move to (copy then delete, spec §3.3). Empty while there is only Personal.
    public var transferTargets: [PickerOption] {
        guard let current = product.space else { return [] }
        return spaces()
            .filter { $0 != current && !$0.isGone && inventory.canEdit($0) }
            .map { PickerOption(id: $0.publicId, name: $0.name) }
    }

    /// Moves the whole item to another space. No undo: the view confirms first.
    public func transfer(_ itemID: UUID, to spaceID: UUID) -> Bool {
        do {
            guard let target = spaces().first(where: { $0.publicId == spaceID }) else { throw ServiceError.notFound }
            try inventory.transfer(try item(itemID), to: target)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func dismissError() { errorMessage = nil }

    // MARK: Helpers

    private func item(_ id: UUID) throws -> InventoryItem {
        let item = try openItems.first(where: { $0.publicId == id }) ?? inventory.item(publicId: id)
        guard let item, !item.isGone else { throw ServiceError.notFound }
        return item
    }

    private func action(_ make: () throws -> UndoableAction) -> UndoableAction? {
        do {
            return try make()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = error.localizedDescription }
    }

    private func groups(in space: Space) throws -> [StockGroup] {
        let now = inventory.currentDate()
        let calendar = inventory.calendar
        let visible = openItems
        let order = try storageLocations.locations(in: space)
        let byLocation = Dictionary(grouping: visible) { $0.storageLocation }
        var groups: [StockGroup] = []
        func group(_ location: StorageLocation?) {
            guard let items = byLocation[location], !items.isEmpty else { return }
            let cards = items
                .sorted {
                    ExpirationStatus.sortKey(expiresAt: $0.expiresAt, now: now, calendar: calendar)
                        < ExpirationStatus.sortKey(expiresAt: $1.expiresAt, now: now, calendar: calendar)
                }
                .map { item in
                    StockItemCard(id: item.publicId, quantity: item.quantity, unit: item.unit,
                                  quantityText: Quantity.format(item.quantity, unit: item.unit, locale: locale),
                                  purchasedAt: item.purchasedAt, expiresAt: item.expiresAt,
                                  level: ExpirationStatus.level(expiresAt: item.expiresAt, now: now, calendar: calendar),
                                  expiryText: ExpirationStatus.cardLabel(expiresAt: item.expiresAt, now: now,
                                                                         calendar: calendar, locale: locale))
                }
            groups.append(StockGroup(id: location?.publicId.uuidString ?? "none", name: location?.name,
                                     totalText: StockSummary.text(for: items, locale: locale) ?? "", items: cards))
        }
        order.forEach(group)
        group(nil)
        return groups
    }

    private func prices() throws -> [PriceRow] {
        try inventory.items(for: product, includeConsumed: true)
            .filter { $0.price != nil }
            .sorted { ($0.purchasedAt ?? $0.createdAt) > ($1.purchasedAt ?? $1.createdAt) }
            .map { item in
                let currency = item.currency ?? inventory.defaultCurrency
                let price = (item.price ?? 0).formatted(.currency(code: currency).locale(locale))
                return PriceRow(id: item.publicId, date: item.purchasedAt, storeName: item.shoppingLocation?.name,
                                priceText: price, quantityText: Quantity.format(item.purchasedQuantity, unit: item.unit, locale: locale))
            }
    }

    private func row(_ event: InventoryEvent) -> HistoryRow {
        let actor = event.createdBy
        let member = product.space?.memberSet.first { $0.userRecordName == actor }
        let isCurrentUser = actor == userRecordName
        return HistoryRow(id: event.publicId, kind: event.kind,
                          quantityText: Quantity.format(event.quantity, unit: event.unit, locale: locale),
                          fromLocation: event.fromLocationName, toLocation: event.toLocationName,
                          occurredAt: event.occurredAt,
                          actorName: isCurrentUser ? nil : member?.displayName,
                          actorSeed: member?.colorSeed ?? actor, isCurrentUser: isCurrentUser)
    }
}

private extension InventoryItem {
    /// The amount bought: what is left plus everything consumed from it.
    var purchasedQuantity: Decimal {
        quantity + consumptionLogSet.reduce(0) { $0 + $1.quantity }
    }
}

/// The amount picker of the consume and move sheets: a stepper and a text field in the item's unit.
/// Valid only for more than 0 and at most the stock item's quantity; the confirm button follows `isValid`.
@MainActor
@Observable
public final class AmountFormModel {
    public let maximum: Decimal
    public let unit: MeasureUnit
    public var text: String
    private let locale: Locale

    public init(maximum: Decimal, unit: MeasureUnit, locale: Locale = .current) {
        self.maximum = maximum
        self.unit = unit
        self.locale = locale
        text = Quantity.formatNumber(maximum, locale: locale)
    }

    public var value: Decimal? { Quantity.parse(text, locale: locale) }
    public var isValid: Bool { value.map { $0 > 0 && $0 <= maximum } ?? false }
    public var maximumText: String { Quantity.format(maximum, unit: unit, locale: locale) }

    /// 0.1 for kilograms, litres and metres; 10 for grams and millilitres; 1 otherwise.
    public var step: Decimal {
        switch unit {
        case .kilogram, .liter, .meter: Decimal(string: "0.1", locale: Locale(identifier: "en_US_POSIX"))!
        case .gram, .milliliter: 10
        default: 1
        }
    }

    public var canIncrement: Bool { (value ?? 0) < maximum }
    public var canDecrement: Bool { (value ?? 0) - step > 0 }

    public func increment() {
        set(min((value ?? 0) + step, maximum))
    }

    public func decrement() {
        let next = (value ?? maximum) - step
        guard next > 0 else { return }
        set(next)
    }

    private func set(_ value: Decimal) {
        text = Quantity.formatNumber(value, locale: locale)
    }
}
