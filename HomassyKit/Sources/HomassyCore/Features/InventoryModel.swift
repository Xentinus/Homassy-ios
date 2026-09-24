import CoreData
import Foundation
import Observation

/// One section of the Inventory grid.
public struct InventorySection: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable { case expiring, location(UUID), noLocation }
    public let kind: Kind
    /// The storage location's name; nil for "Expiring soon" and "No location" (the view localizes those).
    public let title: String?
    public let isFreezer: Bool
    public let cards: [ProductCardData]
    public var id: Kind { kind }
}

/// The Inventory tab: "Expiring soon" (every open item whose level needs attention) first, then one section per
/// storage location in the space's order, then "No location". A card is one product within one section, its
/// stock added up (user choice, 2026-09-24); expiring items are not repeated below. Cards have no actions:
/// a tap opens the product detail, where consume, move, edit and delete live.
@MainActor
@Observable
public final class InventoryModel {
    public let space: Space
    public private(set) var errorMessage: String?

    /// Value snapshots taken at `reload()`. Holding the managed objects instead would not redraw the grid:
    /// reassigning an equal array of references does not notify observers, although their values changed.
    private var entries: [Entry] = []
    private var locations: [LocationEntry] = []
    private let inventory: InventoryService
    private let storage: StorageLocationService
    private let pending: PendingDeletions
    private let locale: Locale

    private struct Entry: Equatable {
        let itemID: UUID
        let productID: UUID
        let name: String
        let brand: String?
        let barcode: String?
        let isEatable: Bool
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
                locale: Locale = .current) {
        self.inventory = inventory
        self.storage = storage
        self.space = space
        self.pending = pending
        self.locale = locale
    }

    public var canEdit: Bool { inventory.canEdit(space) }
    public var isEmpty: Bool { sections.isEmpty }

    public var sections: [InventorySection] {
        let now = inventory.currentDate()
        let calendar = inventory.calendar
        func level(_ entry: Entry) -> ExpirationLevel {
            ExpirationStatus.level(expiresAt: entry.expiresAt, now: now, calendar: calendar)
        }
        func key(_ entry: Entry) -> ExpirationSortKey {
            ExpirationStatus.sortKey(expiresAt: entry.expiresAt, now: now, calendar: calendar)
        }
        let visible = entries.filter { !pending.contains($0.itemID) && !pending.contains($0.productID) }
        let expiring = visible.filter { level($0).isAttention }
        let rest = visible.filter { !level($0).isAttention }

        /// One card per product; `urgentFirst` orders the expiring section by its most urgent item.
        func cards(_ group: [Entry], urgentFirst: Bool) -> [ProductCardData] {
            let built = Dictionary(grouping: group, by: \.productID).values.map { items -> (card: ProductCardData, key: ExpirationSortKey) in
                let product = items[0]
                let first = items.min { key($0) < key($1) }!
                let card = ProductCardData(
                    id: product.productID, name: product.name, brand: product.brand, barcode: product.barcode,
                    isEatable: product.isEatable, isFavorite: product.isFavorite, image: product.image,
                    stockText: StockSummary.text(for: items.map { ($0.quantity, $0.unit) }, locale: locale),
                    expiryLevel: level(first),
                    expiryText: ExpirationStatus.cardLabel(expiresAt: first.expiresAt, now: now,
                                                           calendar: calendar, locale: locale))
                return (card, key(first))
            }
            if urgentFirst {
                return built.sorted {
                    $0.key == $1.key ? $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending : $0.key < $1.key
                }.map(\.card)
            }
            return sortedByName(built.map(\.card), name: \.name)
        }

        var result: [InventorySection] = []
        if !expiring.isEmpty {
            result.append(InventorySection(kind: .expiring, title: nil, isFreezer: false, cards: cards(expiring, urgentFirst: true)))
        }
        let byLocation = Dictionary(grouping: rest, by: \.locationID)
        for location in locations {
            guard let group = byLocation[location.id], !group.isEmpty else { continue }
            result.append(InventorySection(kind: .location(location.id), title: location.name,
                                           isFreezer: location.isFreezer, cards: cards(group, urgentFirst: false)))
        }
        if let loose = byLocation[nil], !loose.isEmpty {
            result.append(InventorySection(kind: .noLocation, title: nil, isFreezer: false, cards: cards(loose, urgentFirst: false)))
        }
        return result
    }

    public func reload() {
        do {
            entries = try inventory.items(in: space).compactMap { item in
                guard !item.isGone, let product = item.product else { return nil }
                return Entry(itemID: item.publicId, productID: product.publicId, name: product.name, brand: product.brand,
                             barcode: product.barcode, isEatable: product.isEatable, isFavorite: product.isFavorite,
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
