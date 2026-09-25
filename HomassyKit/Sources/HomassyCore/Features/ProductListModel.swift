import CoreData
import Foundation
import Observation

/// One card in the Products grid (README "Card layout").
public struct ProductCardData: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let brand: String?
    public let barcode: String?
    public let isFavorite: Bool
    public let image: Data?
    /// Open stock added up per unit; nil when nothing is in stock.
    public let stockText: String?
    /// From the open item that expires first; `.none` without a date.
    public let expiryLevel: ExpirationLevel
    public let expiryText: String?
    /// The product and its stock items: a change by someone else to any of them flashes the card (P5-04).
    public var relatedIDs: Set<UUID> = []
}

public struct ProductSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let cards: [ProductCardData]
}

/// The Products tab: letter sections of cards, search and a category filter. Cards have no delete
/// (user rule); a product deleted from its detail is hidden here while its undo window is open.
@MainActor
@Observable
public final class ProductListModel {
    public let space: Space
    public var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            if searchText != unknownBarcode { unknownBarcode = nil }
            reload()
        }
    }
    /// A scanned code that matched no product; the view offers creating one with it. Cleared once the text changes.
    public private(set) var unknownBarcode: String?
    public var selectedCategory: String? { didSet { if selectedCategory != oldValue { reload() } } }
    public private(set) var categories: [String] = []
    public private(set) var errorMessage: String?

    private var cards: [ProductCardData] = []
    private let products: ProductService
    private let inventory: InventoryService
    private let pending: PendingDeletions
    private let locale: Locale

    public init(products: ProductService, inventory: InventoryService, space: Space, pending: PendingDeletions,
                locale: Locale = .current) {
        self.products = products
        self.inventory = inventory
        self.space = space
        self.pending = pending
        self.locale = locale
    }

    public var canEdit: Bool { products.canEdit(space) }
    public var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty || selectedCategory != nil }

    public var sections: [ProductSection] {
        let visible = cards.filter { !pending.contains($0.id) }
        let grouped = Dictionary(grouping: visible) { Self.sectionKey(for: $0.name, locale: locale) }
        let keys = grouped.keys.sorted { lhs, rhs in
            if lhs == "#" || rhs == "#" { return rhs == "#" && lhs != "#" }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return keys.map { ProductSection(id: $0, cards: grouped[$0] ?? []) }
    }

    public func reload() {
        do {
            categories = try products.categories(in: space)
            if let selected = selectedCategory, !categories.contains(selected) { selectedCategory = nil }
            var found = try products.search(searchText, in: space)
            if let category = selectedCategory {
                found = found.filter { $0.category?.caseInsensitiveCompare(category) == .orderedSame }
            }
            let stock = Dictionary(grouping: try inventory.items(in: space)) { $0.product?.objectID }
            let now = inventory.currentDate()
            let calendar = inventory.calendar
            cards = found.map { product in
                let items = stock[product.objectID] ?? []
                let first = items.min {
                    ExpirationStatus.sortKey(expiresAt: $0.expiresAt, now: now, calendar: calendar)
                        < ExpirationStatus.sortKey(expiresAt: $1.expiresAt, now: now, calendar: calendar)
                }
                return ProductCardData(
                    id: product.publicId, name: product.name, brand: product.brand, barcode: product.barcode,
                    isFavorite: product.isFavorite, image: product.image,
                    stockText: StockSummary.text(for: items, locale: locale),
                    expiryLevel: ExpirationStatus.level(expiresAt: first?.expiresAt, now: now, calendar: calendar),
                    expiryText: ExpirationStatus.cardLabel(expiresAt: first?.expiresAt, now: now,
                                                           calendar: calendar, locale: locale),
                    relatedIDs: Set([product.publicId] + items.map(\.publicId)))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Search by a scanned code (user request, 2026-09-24). A match shows that product, UPC-A and EAN-13 forms
    /// included (`BarcodeRouter`); no match leaves the normalised code in the search field and in `unknownBarcode`.
    public func searchBarcode(_ raw: String, symbology: BarcodeSymbology = .other) {
        do {
            switch try BarcodeRouter(products: products).route(barcode: raw, symbology: symbology, in: space) {
            case .known(let product):
                unknownBarcode = nil
                searchText = product.barcode ?? product.name
            case .unknown(let code):
                unknownBarcode = code
                searchText = code
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func dismissError() { errorMessage = nil }

    static func sectionKey(for name: String, locale: Locale) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let folded = String(first).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .uppercased(with: locale)
        return folded.first?.isLetter == true ? folded : "#"
    }
}
