import CoreData
import Foundation
import Observation

public struct PickerProduct: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    /// The brand, else the category.
    public let subtitle: String?
    public let image: Data?
}

public struct PickerSection: Identifiable, Equatable, Sendable {
    /// The letter, or "#" for names that do not start with a letter.
    public let id: String
    public let products: [PickerProduct]
}

/// The add-stock sheet's first page (P2-08a, option 1A): recent products, then A–Z sections, and search by name,
/// brand, category or barcode, ignoring case and accents. A search without an exact name match offers a new
/// product with that name.
@MainActor
@Observable
public final class ProductPickerModel {
    public static let recentLimit = 5

    public let space: Space
    public var searchText = "" {
        didSet { if searchText != oldValue { reload() } }
    }
    public private(set) var recents: [PickerProduct] = []
    public private(set) var sections: [PickerSection] = []
    /// The trimmed search text when no product has exactly that name.
    public private(set) var createCandidate: String?
    public private(set) var errorMessage: String?

    @ObservationIgnored private let products: ProductService
    @ObservationIgnored private let inventory: InventoryService
    @ObservationIgnored private let pending: PendingDeletions
    @ObservationIgnored private let locale: Locale

    public init(space: Space, products: ProductService, inventory: InventoryService, pending: PendingDeletions,
                locale: Locale = .current) {
        self.space = space
        self.products = products
        self.inventory = inventory
        self.pending = pending
        self.locale = locale
        reload()
    }

    public var isSearching: Bool { searchText.nilIfBlank != nil }
    public var canCreate: Bool { products.canEdit(space) }

    public func reload() {
        let query = searchText.nilIfBlank
        do {
            let found = try products.search(query ?? "", in: space).filter { !pending.contains($0.publicId) }
            sections = LetterSections.group(found.map(Self.row), locale: locale, name: \.name)
                .map { PickerSection(id: $0.key, products: $0.values) }
            recents = try query == nil ? recentProducts(among: found) : []
            createCandidate = query.flatMap { text in
                found.contains { $0.name.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                    ? nil : text
            }
            errorMessage = nil
        } catch {
            sections = []
            recents = []
            createCandidate = nil
            errorMessage = error.localizedDescription
        }
    }

    public func dismissError() { errorMessage = nil }

    /// A scanned code: the matching product, or the normalised code for a new one.
    public func route(barcode: String, symbology: BarcodeSymbology = .other) -> BarcodeRoute? {
        try? BarcodeRouter(products: products).route(barcode: barcode, symbology: symbology, in: space)
    }

    /// The products whose stock was added last, newest first.
    private func recentProducts(among visible: [Product]) throws -> [PickerProduct] {
        let allowed = Set(visible.map(\.objectID))
        let items = try inventory.context.fetchEntities(
            InventoryItem.self, where: NSPredicate(format: "product.space == %@", space),
            sortedBy: [NSSortDescriptor(key: "createdAt", ascending: false)])
        var seen = Set<NSManagedObjectID>()
        var result: [PickerProduct] = []
        for item in items {
            guard let product = item.product, allowed.contains(product.objectID),
                  seen.insert(product.objectID).inserted else { continue }
            result.append(Self.row(product))
            if result.count == Self.recentLimit { break }
        }
        return result
    }

    private static func row(_ product: Product) -> PickerProduct {
        PickerProduct(id: product.publicId, name: product.name,
                      subtitle: product.brand?.nilIfBlank ?? product.category?.nilIfBlank, image: product.image)
    }
}
