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
    public let isFavorite: Bool
    public let notes: String?
    public let image: Data?
    /// The product's web link, opened from the header card.
    public let url: URL?
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

/// One open lot in the detail's single stock list (P2-07a, 2A): the card plus where it is.
public struct StockLotRow: Identifiable, Equatable, Sendable {
    public let card: StockItemCard
    public let locationName: String?
    public let isFreezer: Bool
    public var id: UUID { card.id }
}

/// The full history page's month section ("September 2026"). Events without a date go to "undated", with no title.
public struct HistoryMonth: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let rows: [HistoryRow]
}

/// The inline price chart (P2-07a): the last `ProductDetailModel.trendMonths` months of purchases in the average's
/// currency and unit, oldest first.
public struct PriceTrend: Equatable, Sendable {
    public let points: [PriceEntry]
    public let currency: String
    public let unit: MeasureUnit
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

/// The product detail (README "Product detail layout"): header, one stock list sorted by expiry with consume, move
/// and delete, price trend and history. Every action returns an `UndoableAction` for the toast.
@MainActor
@Observable
public final class ProductDetailModel {
    public let product: Product
    public private(set) var fields: ProductFields?
    /// Every open lot, sorted for the stock list; `stock` hides the ones whose delete is in its undo window.
    private var allLots: [StockLotRow] = []
    public private(set) var priceTrend: PriceTrend?
    /// Every priced purchase, newest first (P4-05); `priceSummary` is the average and the per-store lines.
    public private(set) var priceEntries: [PriceEntry] = []
    public private(set) var priceSummary = PriceSummary(average: nil, stores: [])
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

    /// Open stock lots shown.
    public var stockCount: Int { stock.count }

    /// The stock list (2A): soonest expiry first, no expiry last, then the older purchase.
    public var stock: [StockLotRow] { allLots.filter { !pending.contains($0.id) } }

    /// "3 l" for the stock header, summed per unit like the Products card. Nil without stock.
    public var stockTotalText: String? {
        let lots = stock
        guard !lots.isEmpty else { return nil }
        return StockSummary.text(for: lots.map { ($0.card.quantity, $0.card.unit) }, locale: locale)
    }

    public static let recentHistoryCount = 3
    public static let trendMonths = 6

    /// The history section's rows (3A); the rest is on the history page.
    public var recentHistory: [HistoryRow] { Array(history.prefix(Self.recentHistoryCount)) }

    /// Newest purchase overall, for "Legutóbb …".
    public var latestPrice: PriceEntry? { priceEntries.first }

    /// The history page: every event newest first, in calendar-month sections.
    public var historyByMonth: [HistoryMonth] {
        let calendar = inventory.calendar
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).year().month(.wide)
        var order: [String] = []
        var titles: [String: String] = [:]
        var rows: [String: [HistoryRow]] = [:]
        for row in history {
            let id: String
            if let date = row.occurredAt {
                let parts = calendar.dateComponents([.year, .month], from: date)
                id = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
                if titles[id] == nil { titles[id] = date.formatted(style) }
            } else {
                id = "undated"
                titles[id] = ""
            }
            if rows[id] == nil { order.append(id) }
            rows[id, default: []].append(row)
        }
        return order.map { HistoryMonth(id: $0, title: titles[$0] ?? "", rows: rows[$0] ?? []) }
    }

    public func reload() {
        guard !product.isGone, product.space != nil else {
            fields = nil
            allLots = []
            priceTrend = nil
            priceEntries = []
            priceSummary = PriceSummary(average: nil, stores: [])
            history = []
            openItems = []
            return
        }
        fields = ProductFields(name: product.name, brand: product.brand, category: product.category,
                               barcode: product.barcode, unitName: product.defaultUnit.name(for: 1, locale: locale),
                               isFavorite: product.isFavorite, notes: product.notes, image: product.image,
                               url: product.url.flatMap(URL.init(string:)))
        do {
            openItems = try inventory.items(for: product)
            priceEntries = PriceHistory.entries(for: product, defaultCurrency: inventory.defaultCurrency)
            priceSummary = PriceHistory.summary(of: priceEntries, preferredCurrency: inventory.defaultCurrency)
            allLots = lots()
            priceTrend = trend(priceEntries, average: priceSummary.average)
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

    /// The edit-stock sheet for one item (one lot, the store menu from `locations`).
    public func editForm(for itemID: UUID, locations: ShoppingLocationService) -> StockFormModel? {
        guard let item = try? item(itemID) else { return nil }
        return StockFormModel(mode: .edit(item), inventory: inventory, products: products, storage: storageLocations,
                              locations: locations, locale: locale)
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

    private func card(_ item: InventoryItem, now: Date, calendar: Calendar) -> StockItemCard {
        StockItemCard(id: item.publicId, quantity: item.quantity, unit: item.unit,
                      quantityText: Quantity.format(item.quantity, unit: item.unit, locale: locale),
                      purchasedAt: item.purchasedAt, expiresAt: item.expiresAt,
                      level: ExpirationStatus.level(expiresAt: item.expiresAt, now: now, calendar: calendar),
                      expiryText: ExpirationStatus.cardLabel(expiresAt: item.expiresAt, now: now, calendar: calendar,
                                                             locale: locale))
    }

    private func lots() -> [StockLotRow] {
        let now = inventory.currentDate()
        let calendar = inventory.calendar
        return openItems
            .sorted { a, b in
                let left = ExpirationStatus.sortKey(expiresAt: a.expiresAt, now: now, calendar: calendar)
                let right = ExpirationStatus.sortKey(expiresAt: b.expiresAt, now: now, calendar: calendar)
                if left != right { return left < right }
                return (a.purchasedAt ?? .distantFuture) < (b.purchasedAt ?? .distantFuture)
            }
            .map { item in
                StockLotRow(card: card(item, now: now, calendar: calendar), locationName: item.storageLocation?.name,
                            isFreezer: item.storageLocation?.isFreezer ?? false)
            }
    }

    private func trend(_ entries: [PriceEntry], average: PriceSummary.Average?) -> PriceTrend? {
        guard let average,
              let start = inventory.calendar.date(byAdding: .month, value: -Self.trendMonths, to: inventory.currentDate())
        else { return nil }
        let points = entries
            .filter { $0.currency == average.currency && $0.unit == average.unit && $0.date >= start }
            .sorted { $0.date < $1.date }
        return points.isEmpty ? nil : PriceTrend(points: points, currency: average.currency, unit: average.unit)
    }

    // MARK: Price trend

    /// One store's purchases for the chart, oldest first.
    public func chartEntries(storeKey: String) -> [PriceEntry] { PriceHistory.chart(priceEntries, storeKey: storeKey) }

    public func priceText(_ value: Decimal, currency: String) -> String {
        value.formatted(.currency(code: currency).locale(locale))
    }

    /// "450 Ft / l".
    public func unitPriceText(_ value: Decimal, currency: String, unit: MeasureUnit) -> String {
        CoreLocalization.format("price.perUnit %@ %@", locale: locale, priceText(value, currency: currency),
                                unit.shortLabel(for: 1, locale: locale))
    }

    public func unitPriceText(_ entry: PriceEntry) -> String {
        unitPriceText(entry.unitPrice, currency: entry.currency, unit: entry.unit)
    }

    public func quantityText(_ entry: PriceEntry) -> String {
        Quantity.format(entry.quantity, unit: entry.unit, locale: locale)
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
