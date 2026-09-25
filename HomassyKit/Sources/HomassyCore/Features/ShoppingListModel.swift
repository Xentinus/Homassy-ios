import Foundation
import Observation

/// One shopping list: the items still to buy and the item actions (adding is `AddItemFlowModel`).
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

    public let list: ShoppingList
    public private(set) var listName = ""
    public private(set) var errorMessage: String?
    private var remainingAll: [Row] = []

    @ObservationIgnored private let service: ShoppingService
    @ObservationIgnored private let inventory: InventoryService
    @ObservationIgnored private let undoQueue: UndoQueue
    @ObservationIgnored private let pending: PendingDeletions
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var items: [UUID: ShoppingListItem] = [:]

    /// Items waiting in an undo window (deleted or bought) are filtered out here. `pending` is observable,
    /// so views update when an undo reveals them again.
    public var remaining: [Row] { remainingAll.filter { !pending.contains($0.id) } }
    public var totalCount: Int { remaining.count }

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

    /// Drag and drop on the card grid: moves `id` to where `target` is.
    public func moveItem(_ id: UUID, onto target: UUID) {
        let ids = remaining.map(\.id)
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return }
        moveRemaining(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    public func dismissError() { errorMessage = nil }

    private func row(for item: ShoppingListItem) -> Row {
        Row(id: item.publicId, name: ShoppingService.displayName(of: item),
            quantityText: Quantity.format(item.quantity, unit: item.unit, locale: locale),
            note: item.note, storeName: item.shoppingLocation?.name, deadline: item.deadline,
            productID: item.product?.publicId, image: item.product?.image)
    }
}
