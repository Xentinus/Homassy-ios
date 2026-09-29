import Foundation
import Observation

/// The Shopping tab (P4-03a, the Reminders "All" pattern): every item still to buy in a space, as one section per
/// list or per store, with an optional list filter. Replaces the per-list `ShoppingListModel`; list management
/// stays in `ShoppingListsModel`, and adding is `AddItemFlowModel`. Bought items leave the list (2026-09-25).
@MainActor
@Observable
public final class ShoppingOverviewModel {
    public struct ListChip: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let color: String?
        /// Items still to buy, without the ones waiting in an undo window.
        public let remaining: Int
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let listID: UUID
        public let listName: String
        public let listColor: String?
        public let name: String
        public let quantityText: String
        public let note: String?
        public let storeName: String?
        public let storeID: UUID?
        public let deadline: Date?
        /// Drawn like stock expiry (README "Card layout"): yellow within 14 days, red once the deadline passed.
        public let deadlineLevel: ExpirationLevel
        /// Set for product items: the card shows the product photo.
        public let productID: UUID?
        public let image: Data?
    }

    public struct Section: Identifiable, Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case list(ListChip)
            case store(id: UUID, title: String, distance: Double?)
            case noStore
        }

        public let kind: Kind
        public let rows: [Row]

        public var id: String {
            switch kind {
            case .list(let chip): "list-\(chip.id.uuidString)"
            case .store(let id, _, _): "store-\(id.uuidString)"
            case .noStore: "no-store"
            }
        }
    }

    private struct ListInfo: Equatable {
        let id: UUID
        let name: String
        let color: String?
    }

    public let space: Space
    public private(set) var errorMessage: String?

    /// nil = "Mind". Remembered per space.
    public var filter: UUID? {
        didSet { if filter != oldValue { preferences.setFilter(filter, for: space.publicId) } }
    }

    /// Remembered per device.
    public var grouping: ShoppingGrouping {
        didSet { if grouping != oldValue { preferences.grouping = grouping } }
    }

    /// Value snapshots (P2-08 gotcha): list order, then item order.
    private var lists: [ListInfo] = []
    private var allRows: [Row] = []

    @ObservationIgnored private let service: ShoppingService
    @ObservationIgnored private let undoQueue: UndoQueue
    @ObservationIgnored private let pending: PendingDeletions
    @ObservationIgnored private let preferences: ShoppingHomePreferences
    @ObservationIgnored private let distance: (UUID) -> Double?
    @ObservationIgnored private let storeTitle: (UUID) -> String?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var items: [UUID: ShoppingListItem] = [:]

    /// `distance` and `storeTitle` come from `StoreDirectory`; reading them inside a view body lets SwiftUI follow
    /// the directory's observable location.
    public init(service: ShoppingService, space: Space, undoQueue: UndoQueue, pending: PendingDeletions,
                preferences: ShoppingHomePreferences, distance: @escaping (UUID) -> Double?,
                storeTitle: @escaping (UUID) -> String?, locale: Locale = .current, calendar: Calendar = .current,
                now: @escaping () -> Date = { Date() }) {
        self.service = service
        self.space = space
        self.undoQueue = undoQueue
        self.pending = pending
        self.preferences = preferences
        self.distance = distance
        self.storeTitle = storeTitle
        self.locale = locale
        self.calendar = calendar
        self.now = now
        filter = preferences.filter(for: space.publicId)
        grouping = preferences.grouping
        reload()
    }

    // MARK: Derived state (pending rows are filtered here, so an undo shows them again)

    private var visibleRows: [Row] { allRows.filter { !pending.contains($0.id) } }

    public var chips: [ListChip] {
        let counts = Dictionary(grouping: visibleRows, by: \.listID).mapValues(\.count)
        return lists.map { ListChip(id: $0.id, name: $0.name, color: $0.color, remaining: counts[$0.id] ?? 0) }
    }

    public var totalCount: Int { visibleRows.count }
    public var hasLists: Bool { !lists.isEmpty }
    public var showsStrip: Bool { lists.count >= 2 }
    public var showsListHeaders: Bool { grouping == .list && filter == nil && showsStrip }
    public var canReorder: Bool { grouping == .list }

    public var sections: [Section] {
        let rows = visibleRows.filter { filter == nil || $0.listID == filter }
        switch grouping {
        case .list:
            let byList = Dictionary(grouping: rows, by: \.listID)
            return chips.compactMap { chip in
                guard let rows = byList[chip.id], !rows.isEmpty else { return nil }
                return Section(kind: .list(chip), rows: rows)
            }
        case .store:
            var byStore: [UUID: [Row]] = [:]
            var loose: [Row] = []
            for row in rows {
                if let id = row.storeID { byStore[id, default: []].append(row) } else { loose.append(row) }
            }
            let stores = byStore.map { id, rows in
                Section(kind: .store(id: id, title: storeTitle(id) ?? rows[0].storeName ?? "", distance: distance(id)),
                        rows: rows)
            }
            .sorted(by: Self.storeOrder)
            return loose.isEmpty ? stores : stores + [Section(kind: .noStore, rows: loose)]
        }
    }

    /// Nearest first; a store with a distance before one without; otherwise A–Z.
    private static func storeOrder(_ left: Section, _ right: Section) -> Bool {
        guard case let .store(_, leftTitle, leftDistance) = left.kind,
              case let .store(_, rightTitle, rightDistance) = right.kind else { return false }
        switch (leftDistance, rightDistance) {
        case let (l?, r?) where l != r: return l < r
        case (.some, nil): return true
        case (nil, .some): return false
        default: return leftTitle.localizedStandardCompare(rightTitle) == .orderedAscending
        }
    }

    // MARK: Actions

    public func reload() {
        do {
            let all = try service.lists(in: space).filter { !$0.isGone }
            var rows: [Row] = []
            var map: [UUID: ShoppingListItem] = [:]
            for list in all {
                for item in try service.unpurchasedItems(in: list) {
                    map[item.publicId] = item
                    rows.append(row(for: item, in: list))
                }
            }
            lists = all.map { ListInfo(id: $0.publicId, name: $0.name, color: $0.color) }
            items = map
            allRows = rows
            if let filter, !lists.contains(where: { $0.id == filter }) { self.filter = nil }
        } catch {
            errorMessage = FeatureError.message(for: error)
        }
    }

    public func item(for id: UUID) -> ShoppingListItem? { items[id] }

    public func delete(_ id: UUID) {
        guard let item = items[id] else { return }
        undoQueue.enqueue(ShoppingActions.deleteItem(item, service: service, pending: pending))
    }

    /// Drag and drop on the card grid: moves `id` to where `target` is. Only in list grouping, only within a list.
    public func moveItem(_ id: UUID, onto target: UUID) {
        guard canReorder, id != target,
              let dragged = allRows.first(where: { $0.id == id }),
              let dropped = allRows.first(where: { $0.id == target }),
              dragged.listID == dropped.listID else { return }
        let listRows = allRows.filter { $0.listID == dragged.listID }
        let visible = listRows.filter { !pending.contains($0.id) }
        let ids = visible.map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return }
        let ordered = Reordering.move(visible.compactMap { items[$0.id] }, fromOffsets: IndexSet(integer: from),
                                      toOffset: to > from ? to + 1 : to)
        let hidden = listRows.filter { pending.contains($0.id) }.compactMap { items[$0.id] }
        do {
            try service.reorderItems(ordered + hidden)
        } catch {
            errorMessage = FeatureError.message(for: error)
        }
        reload()
    }

    public func dismissError() { errorMessage = nil }

    private func row(for item: ShoppingListItem, in list: ShoppingList) -> Row {
        Row(id: item.publicId, listID: list.publicId, listName: list.name, listColor: list.color,
            name: ShoppingService.displayName(of: item),
            quantityText: Quantity.format(item.quantity, unit: item.unit, locale: locale),
            note: item.note, storeName: item.shoppingLocation?.name, storeID: item.shoppingLocation?.publicId,
            deadline: item.deadline,
            deadlineLevel: ExpirationStatus.level(expiresAt: item.deadline, now: now(), calendar: calendar),
            productID: item.product?.publicId, image: item.product?.image)
    }
}
