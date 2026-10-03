import CoreData
import Foundation
import Observation

/// The Inventory expiry grouping's time bands (P2-08e, user pick 3A), by the days until a product's earliest item
/// expires. The 14-day edge is where a card turns yellow.
public enum ExpiryBucket: Int, Sendable, CaseIterable {
    case expired, today, soon, later, undated

    public init(daysUntilExpiration days: Int?) {
        guard let days else { self = .undated; return }
        if days < 0 { self = .expired } else if days == 0 { self = .today }
        else if days <= ExpirationStatus.soonDays { self = .soon } else { self = .later }
    }
}

/// One section of the Inventory grid.
public struct InventorySection: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable { case expiring, location(UUID), noLocation, letter(String), expiry(ExpiryBucket) }
    public let kind: Kind
    /// The storage location's name; nil for every other kind (the view localizes those, and a letter is its key).
    public let title: String?
    public let isFreezer: Bool
    public let cards: [ProductCardData]
    public var id: Kind { kind }

    /// The key of a letter section, for the letter index.
    public var letter: String? {
        if case .letter(let key) = kind { return key }
        return nil
    }
}

/// The Inventory tab, grouped by location ("Expiring soon" first, then one section per storage location in the
/// space's order, then "No location"), by name or by expiry (P2-08e). A card is one product within one section, its
/// stock added up (user choice, 2026-09-24); expiring items are not repeated below. Cards have no actions:
/// a tap opens the product detail, where consume, move, edit and delete live.
@MainActor
@Observable
public final class InventoryModel {
    public let space: Space
    public private(set) var errorMessage: String?
    /// Remembered per device (P2-08e).
    public var grouping: InventoryGrouping {
        didSet { if grouping != oldValue { preferences.grouping = grouping } }
    }

    /// Value snapshots taken at `reload()`. Holding the managed objects instead would not redraw the grid:
    /// reassigning an equal array of references does not notify observers, although their values changed.
    private var entries: [Entry] = []
    private var locations: [LocationEntry] = []
    private let inventory: InventoryService
    private let storage: StorageLocationService
    private let pending: PendingDeletions
    private let preferences: InventoryPreferences
    private let locale: Locale

    private struct Entry: Equatable {
        let itemID: UUID
        let productID: UUID
        let name: String
        let brand: String?
        let barcode: String?
        let isFavorite: Bool
        let image: Data?
        let quantity: Decimal
        let unit: MeasureUnit
        let expiresAt: Date?
        let locationID: UUID?
    }

    private struct LocationEntry: Equatable {
        let id: UUID
        let name: String
        let isFreezer: Bool
    }

    public init(inventory: InventoryService, storage: StorageLocationService, space: Space, pending: PendingDeletions,
                preferences: InventoryPreferences, locale: Locale = .current) {
        self.inventory = inventory
        self.storage = storage
        self.space = space
        self.pending = pending
        self.preferences = preferences
        self.locale = locale
        grouping = preferences.grouping
    }

    public var canEdit: Bool { inventory.canEdit(space) }
    public var isEmpty: Bool { sections.isEmpty }

    public var showsLetterIndex: Bool { grouping == .name && sections.count > 1 }

    public var sections: [InventorySection] {
        let context = Context(now: inventory.currentDate(), calendar: inventory.calendar, locale: locale)
        let visible = entries.filter { !pending.contains($0.itemID) && !pending.contains($0.productID) }
        switch grouping {
        case .location: return locationSections(visible, context)
        case .name: return nameSections(visible, context)
        case .expiry: return expirySections(visible, context)
        }
    }

    private struct Context {
        let now: Date
        let calendar: Calendar
        let locale: Locale

        func level(_ entry: Entry) -> ExpirationLevel {
            ExpirationStatus.level(expiresAt: entry.expiresAt, now: now, calendar: calendar)
        }

        func key(_ entry: Entry) -> ExpirationSortKey {
            ExpirationStatus.sortKey(expiresAt: entry.expiresAt, now: now, calendar: calendar)
        }
    }

    /// One card per product: its stock added up, and the expiry of the item that expires first (`first`).
    /// `places` fills the card's "Fridge, Pantry" line (name and expiry groupings).
    private func productCards(_ group: [Entry], _ context: Context, places: Bool) -> [(card: ProductCardData, first: Entry)] {
        Dictionary(grouping: group, by: \.productID).values.map { items in
            let product = items[0]
            let first = items.min { context.key($0) < context.key($1) }!
            let card = ProductCardData(
                id: product.productID, name: product.name, brand: product.brand, barcode: product.barcode,
                isFavorite: product.isFavorite, image: product.image,
                stockText: StockSummary.text(for: items.map { ($0.quantity, $0.unit) }, locale: context.locale),
                expiryLevel: context.level(first),
                expiryText: ExpirationStatus.cardLabel(expiresAt: first.expiresAt, now: context.now,
                                                       calendar: context.calendar, locale: context.locale),
                relatedIDs: Set([product.productID] + items.map(\.itemID)),
                placesText: places ? placesText(items) : nil)
            return (card, first)
        }
    }

    /// Most urgent first (expired, then by date), then by name.
    private static func byExpiry(_ built: [(card: ProductCardData, first: Entry)], _ context: Context) -> [ProductCardData] {
        built.sorted {
            let left = context.key($0.first), right = context.key($1.first)
            return left == right ? $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending : left < right
        }.map(\.card)
    }

    /// The places of a product's items in the space's location order, "No location" last.
    private func placesText(_ items: [Entry]) -> String {
        let ids = Set(items.map(\.locationID))
        var names = locations.filter { ids.contains($0.id) }.map(\.name)
        if ids.contains(nil) { names.append(CoreLocalization.string("inventory.places.noLocation", locale: locale)) }
        return names.joined(separator: ", ")
    }

    /// "Expiring soon" (every open item whose level needs attention) first, then one section per storage location in
    /// the space's order, then "No location". A card is one product within one section; expiring items are not
    /// repeated below.
    private func locationSections(_ visible: [Entry], _ context: Context) -> [InventorySection] {
        let expiring = visible.filter { context.level($0).isAttention }
        let rest = visible.filter { !context.level($0).isAttention }
        func cards(_ group: [Entry]) -> [ProductCardData] {
            sortedByName(productCards(group, context, places: false).map(\.card), name: \.name)
        }

        var result: [InventorySection] = []
        if !expiring.isEmpty {
            result.append(InventorySection(kind: .expiring, title: nil, isFreezer: false,
                                           cards: Self.byExpiry(productCards(expiring, context, places: false), context)))
        }
        let byLocation = Dictionary(grouping: rest, by: \.locationID)
        for location in locations {
            guard let group = byLocation[location.id], !group.isEmpty else { continue }
            result.append(InventorySection(kind: .location(location.id), title: location.name,
                                           isFreezer: location.isFreezer, cards: cards(group)))
        }
        if let loose = byLocation[nil], !loose.isEmpty {
            result.append(InventorySection(kind: .noLocation, title: nil, isFreezer: false, cards: cards(loose)))
        }
        return result
    }

    /// Letter sections, one card per product across all places (user pick 2, 5A, 6C).
    private func nameSections(_ visible: [Entry], _ context: Context) -> [InventorySection] {
        LetterSections.group(productCards(visible, context, places: true).map(\.card), locale: locale, name: \.name).map {
            InventorySection(kind: .letter($0.key), title: nil, isFreezer: false, cards: $0.values)
        }
    }

    /// Time bands by each product's earliest item, most urgent first within a band (user pick 3A).
    private func expirySections(_ visible: [Entry], _ context: Context) -> [InventorySection] {
        let byBucket = Dictionary(grouping: productCards(visible, context, places: true)) {
            ExpiryBucket(daysUntilExpiration: ExpirationStatus.daysUntilExpiration($0.first.expiresAt, now: context.now,
                                                                                   calendar: context.calendar))
        }
        return ExpiryBucket.allCases.compactMap { bucket in
            guard let group = byBucket[bucket], !group.isEmpty else { return nil }
            return InventorySection(kind: .expiry(bucket), title: nil, isFreezer: false, cards: Self.byExpiry(group, context))
        }
    }

    public func reload() {
        do {
            entries = try inventory.items(in: space).compactMap { item in
                guard !item.isGone, let product = item.product else { return nil }
                return Entry(itemID: item.publicId, productID: product.publicId, name: product.name, brand: product.brand,
                             barcode: product.barcode, isFavorite: product.isFavorite,
                             image: product.image, quantity: item.quantity, unit: item.unit, expiresAt: item.expiresAt,
                             locationID: item.storageLocation?.publicId)
            }
            locations = try storage.locations(in: space).map { LocationEntry(id: $0.publicId, name: $0.name, isFreezer: $0.isFreezer) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func dismissError() { errorMessage = nil }
}
