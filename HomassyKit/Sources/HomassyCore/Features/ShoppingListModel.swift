import Foundation
import Observation

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
        public let isPurchased: Bool
        /// Set for product items: the card opens the product detail and shows its photo.
        public let productID: UUID?
        public let image: Data?
    }

    public struct Suggestion: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
    }

    public let list: ShoppingList
    public private(set) var listName = ""
    public var showPurchased = true
    public var draftText = "" {
        didSet { if draftText != oldValue { refreshSuggestions() } }
    }
    public private(set) var suggestions: [Suggestion] = []
    public private(set) var errorMessage: String?
    private var remainingAll: [Row] = []
    private var purchasedAll: [Row] = []

    @ObservationIgnored private let service: ShoppingService
    @ObservationIgnored private let undoQueue: UndoQueue
    @ObservationIgnored private let pending: PendingDeletions
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var items: [UUID: ShoppingListItem] = [:]
    @ObservationIgnored private var suggestionProducts: [UUID: Product] = [:]

    /// Items waiting in the delete undo window are filtered out here. `pending` is observable,
    /// so views update when an undo reveals them again.
    public var remaining: [Row] { remainingAll.filter { !pending.contains($0.id) } }
    public var purchased: [Row] { purchasedAll.filter { !pending.contains($0.id) } }
    public var purchasedCount: Int { purchased.count }
    public var totalCount: Int { remaining.count + purchased.count }
    public var canAddDraft: Bool { !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public init(service: ShoppingService, list: ShoppingList, undoQueue: UndoQueue, pending: PendingDeletions,
                locale: Locale = .current) {
        self.service = service
        self.list = list
        self.undoQueue = undoQueue
        self.pending = pending
        self.locale = locale
        reload()
    }

    public func reload() {
        guard !list.isGone else {
            remainingAll = []
            purchasedAll = []
            items = [:]
            return
        }
        do {
            listName = list.name
            let open = try service.unpurchasedItems(in: list)
            let done = try service.purchasedItems(in: list)
            items = Dictionary((open + done).map { ($0.publicId, $0) }, uniquingKeysWith: { first, _ in first })
            remainingAll = open.map(row(for:))
            purchasedAll = done.map(row(for:))
        } catch {
            errorMessage = FeatureError.message(for: error)
        }
    }

    public func item(for id: UUID) -> ShoppingListItem? { items[id] }

    public func toggle(_ id: UUID) {
        guard let item = items[id] else { return }
        undoQueue.enqueue(ShoppingActions.togglePurchased(item, service: service))
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
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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

    public func clearPurchased() {
        do {
            try service.clearPurchased(in: list)
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
            isPurchased: item.isPurchased, productID: item.product?.publicId, image: item.product?.image)
    }
}
