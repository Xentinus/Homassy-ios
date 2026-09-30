import CoreData
import Foundation
import HomassyShared

/// Counts the rows that left the shopping Live Activity while it runs (N-04). A row that comes back (undo in the app)
/// stops counting. `carriedDone` is the count an earlier app process already showed on the activity.
public struct ShoppingActivityProgress: Equatable, Sendable {
    public private(set) var openKeys: Set<String>
    public private(set) var doneKeys: Set<String> = []
    public let carriedDone: Int

    public init(openKeys: Set<String>, carriedDone: Int = 0) {
        self.openKeys = openKeys
        self.carriedDone = carriedDone
    }

    public var doneCount: Int { carriedDone + doneKeys.count }

    public mutating func observe(openKeys current: Set<String>) {
        doneKeys.formUnion(openKeys.subtracting(current))
        doneKeys.subtract(current)
        openKeys = current
    }
}

/// Builds the shopping Live Activity's content (N-04): the open items of one store or chain from every list of a
/// household (D5 A, D6 A, D10 A), merged by product and unit (D7 A), with quantities (D8 A). Names are cut to
/// 40 characters for ActivityKit's 4 KB limit.
@MainActor
public enum ShoppingActivityState {
    public static let maxNameLength = 40

    public static func matches(_ item: ShoppingListItem, _ scope: ShoppingActivityScope) -> Bool {
        guard let store = item.shoppingLocation, !store.isGone else { return false }
        switch scope {
        case let .store(id): return store.publicId == id
        case let .stores(ids): return ids.contains(store.publicId)
        case let .chain(key): return ChainKey.make(store.name) == key
        }
    }

    /// Lists in list order, items in item order; bought and undo-pending items left out.
    public static func openItems(scope: ShoppingActivityScope, in space: Space, service: ShoppingService,
                                 pending: PendingDeletions) throws -> [ShoppingListItem] {
        try service.lists(in: space).filter { !$0.isGone }.flatMap { list in
            try service.unpurchasedItems(in: list).filter { !pending.contains($0.publicId) && matches($0, scope) }
        }
    }

    /// One row per product and unit (quantities added), one row per name-only item; the first occurrence decides
    /// the order.
    public static func rows(for items: [ShoppingListItem], locale: Locale) -> [ShoppingActivityItem] {
        var order: [String] = []
        var groups: [String: [ShoppingListItem]] = [:]
        for item in items {
            let key = item.product.flatMap { $0.isGone ? nil : "p:\($0.publicId.uuidString):\(item.unit.rawValue)" }
                ?? "i:\(item.publicId.uuidString)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.compactMap { key in
            guard let group = groups[key], let first = group.first else { return nil }
            let total = group.reduce(Decimal(0)) { $0 + $1.quantity }
            return ShoppingActivityItem(id: key, itemIDs: group.map(\.publicId),
                                        name: truncated(ShoppingService.displayName(of: first)),
                                        quantity: Quantity.format(total, unit: first.unit, locale: locale))
        }
    }

    /// The store's name; for several nearby stores "2 közeli bolt", counting the stores that have open items (one: its
    /// name; none open: the stores that still exist); for a chain the name most of
    /// its open items' stores spell. Nil when the store(s) are gone, or for a chain without open items (the
    /// coordinator then keeps the last title).
    public static func title(scope: ShoppingActivityScope, in space: Space, items: [ShoppingListItem],
                             locations: ShoppingLocationService, locale: Locale = .current) -> String? {
        func name(_ id: UUID) -> String? {
            (try? locations.location(publicId: id, in: space)).flatMap { $0.isGone ? nil : $0.name }
        }
        switch scope {
        case let .store(id):
            return name(id).map(truncated)
        case let .stores(ids):
            let open = Set(items.compactMap { $0.shoppingLocation?.publicId })
            // The stores with open items; when nothing is open (all done), the stores that still exist.
            let withItems = ids.filter(open.contains).compactMap(name)
            let names = withItems.isEmpty ? ids.compactMap(name) : withItems
            switch names.count {
            case 0: return nil
            case 1: return truncated(names[0])
            default: return truncated(CoreLocalization.format("shoppingActivity.nearbyStores %lld", locale: locale, names.count))
            }
        case .chain:
            let name = ChainKey.displayName(of: items.compactMap { $0.shoppingLocation?.name })
            return name.isEmpty ? nil : truncated(name)
        }
    }

    public static func listCount(of items: [ShoppingListItem]) -> Int {
        Set(items.compactMap { $0.shoppingList?.publicId }).count
    }

    public static func content(title: String, spaceName: String, listCount: Int, rows: [ShoppingActivityItem],
                               doneCount: Int, canTick: Bool) -> ShoppingActivityContent {
        ShoppingActivityContent(title: truncated(title), spaceName: truncated(spaceName), listCount: listCount,
                                remainingCount: rows.count, doneCount: doneCount,
                                nextItems: Array(rows.prefix(ShoppingActivityContent.maxNextItems)), canTick: canTick)
    }

    public static func truncated(_ text: String) -> String {
        text.count <= maxNameLength ? text : String(text.prefix(maxNameLength - 1)) + "…"
    }
}
