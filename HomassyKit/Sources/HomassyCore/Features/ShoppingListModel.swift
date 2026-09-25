import Foundation
import Observation

/// One shopping list: the items still to buy, the quick add bar and the item actions.
/// Bought items leave the list (user decision, 2026-09-25), so there is no bought section.
@MainActor
@Observable
public final class ShoppingListModel {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let quantityText: String
        public let note: String?
        public let storeName: String?
        public let deadline: Date?
        /// Set for product items: the card shows the product photo.
        public let productID: UUID?
        public let image: Data?
    }

    public struct Suggestion: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
    }

    public let list: ShoppingList
    public private(set) var listName = ""
    public var draftText = "" {
        didSet { if draftText != oldValue { refreshSuggestions() } }
    }
    public private(set) var suggestions: [Suggestion] = []
    public private(set) var errorMessage: String?
    private var remainingAll: [Row] = []

    @ObservationIgnored private let service: ShoppingService
    @ObservationIgnored private let inventory: InventoryService
    @ObservationIgnored private let undoQueue: UndoQueue
    @ObservationIgnored private let pending: PendingDeletions
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var items: [UUID: ShoppingListItem] = [:]
    @ObservationIgnored private var suggestionProducts: [UUID: Product] = [:]

    /// Items waiting in an undo window (deleted or bought) are filtered out here. `pending` is observable,
    /// so views update when an undo reveals them again.
    public var remaining: [Row] { remainingAll.filter { !pending.contains($0.id) } }
    public var totalCount: Int { remaining.count }
    public var canAddDraft: Bool { draftText.nilIfBlank != nil }

    public init(service: ShoppingService, inventory: InventoryService, list: ShoppingList, undoQueue: UndoQueue,
                pending: PendingDeletions, locale: Locale = .current) {
        self.service = service
        self.inventory = inventory
        self.list = list
        self.undoQueue = undoQueue
        self.pending = pending
        self.locale = locale
        reload()
    }

    public func reload() {
        guard !list.isGone else {
            remainingAll = []
            items = [:]
            return
        }
        do {
            listName = list.name
            let open = try service.unpurchasedItems(in: list)
            items = Dictionary(open.map { ($0.publicId, $0) }, uniquingKeysWith: { first, _ in first })
            remainingAll = open.map(row(for:))
        } catch {
            errorMessage = FeatureError.message(for: error)
        }
    }

    public func item(for id: UUID) -> ShoppingListItem? { items[id] }

    /// The checkbox: buys the whole quantity into inventory, undoable.
    public func quickPurchase(_ id: UUID) {
        guard let item = items[id] else { return }
        do {
            undoQueue.enqueue(try ShoppingPurchase.quickPurchase(item, shopping: service, inventory: inventory,
                                                                 pending: pending))
        } catch {
            errorMessage = FeatureError.message(for: error)
        }
        reload()
    }

    public func delete(_ id: UUID) {
        guard let item = items[id] else { return }
        undoQueue.enqueue(ShoppingActions.deleteItem(item, service: service, pending: pending))
    }

    public func moveRemaining(fromOffsets source: IndexSet, toOffset destination: Int) {
        let ordered = Reordering.move(remaining.compactMap { items[$0.id] }, fromOffsets: source, toOffset: destination)
        let hidden = remainingAll.filter { pending.contains($0.id) }.compactMap { items[$0.id] }
        do {
            try service.reorderItems(ordered + hidden)
        } catch {
            errorMessage = FeatureError.message(for: error)
        }
        reload()
    }

    public func addDraft() {
        guard let text = draftText.nilIfBlank else { return }
        let match = suggestionProducts.values.first {
            $0.name.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        do {
            if let match {
                try service.addItem(to: list, product: match)
            } else {
                try service.addItem(to: list, customName: text)
            }
            draftText = ""
        } catch {
            errorMessage = FeatureError.message(for: error)
        }
        reload()
    }

    public func addSuggestion(_ id: UUID) {
        guard let product = suggestionProducts[id] else { return }
        do {
            try service.addItem(to: list, product: product)
            draftText = ""
        } catch {
            errorMessage = FeatureError.message(for: error)
        }
        reload()
    }

    public func dismissError() { errorMessage = nil }

    private func refreshSuggestions() {
        guard let space = list.space else {
            suggestions = []
            suggestionProducts = [:]
            return
        }
        let products = (try? service.productSuggestions(matching: draftText, in: space)) ?? []
        suggestionProducts = Dictionary(products.map { ($0.publicId, $0) }, uniquingKeysWith: { first, _ in first })
        suggestions = products.map { Suggestion(id: $0.publicId, name: $0.name) }
    }

    private func row(for item: ShoppingListItem) -> Row {
        Row(id: item.publicId, name: ShoppingService.displayName(of: item),
            quantityText: Quantity.format(item.quantity, unit: item.unit, locale: locale),
            note: item.note, storeName: item.shoppingLocation?.name, deadline: item.deadline,
            productID: item.product?.publicId, image: item.product?.image)
    }
}
