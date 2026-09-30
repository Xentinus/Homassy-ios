import Foundation

/// Which items a shopping Live Activity covers (N-04 D5 A, D10 A, D11): one saved store, several saved stores within
/// 150 m of the user (one household, sorted by `uuidString`), or every store of a chain when the user stands at a
/// branch that is not saved. The chain is a `ChainKey` (lowercased, no diacritics).
public enum ShoppingActivityScope: Codable, Hashable, Sendable {
    case store(UUID)
    case stores([UUID])
    case chain(String)

    /// Store scopes end when their stores are gone; a chain scope keeps its last title while nothing is open.
    public var isChain: Bool {
        switch self {
        case .chain: true
        case .store, .stores: false
        }
    }
}

/// One row on the shopping Live Activity. The same product in the same unit from several lists is one row (D7 A),
/// so one tick buys every list item in `itemIDs`.
public struct ShoppingActivityItem: Codable, Hashable, Identifiable, Sendable {
    /// Stable across updates: `p:<product>:<unit>` for products, `i:<item>` for name-only items.
    public let id: String
    public let itemIDs: [UUID]
    public let name: String
    /// The added quantity in the item's unit, formatted by the app ("3 l").
    public let quantity: String

    public init(id: String, itemIDs: [UUID], name: String, quantity: String) {
        self.id = id
        self.itemIDs = itemIDs
        self.name = name
        self.quantity = quantity
    }
}

/// The shopping Live Activity's changing part (`ShoppingActivityAttributes.ContentState`). Kept small: ActivityKit
/// caps attributes plus state at 4 KB, and the builder shortens every name to 40 characters.
public struct ShoppingActivityContent: Codable, Hashable, Sendable {
    public static let maxNextItems = 3

    /// The store's name, or the chain's name at an unsaved branch.
    public var title: String
    public var spaceName: String
    /// How many lists the open items come from; the caption shows it from two up.
    public var listCount: Int
    public var remainingCount: Int
    /// Rows that left since the activity started: bought here, in the app, or removed by someone else.
    public var doneCount: Int
    public var nextItems: [ShoppingActivityItem]
    /// False in a read-only household: the activity shows the items without tick buttons.
    public var canTick: Bool

    public init(title: String, spaceName: String, listCount: Int, remainingCount: Int, doneCount: Int,
                nextItems: [ShoppingActivityItem], canTick: Bool) {
        self.title = title
        self.spaceName = spaceName
        self.listCount = listCount
        self.remainingCount = remainingCount
        self.doneCount = doneCount
        self.nextItems = nextItems
        self.canTick = canTick
    }

    public var isFinished: Bool { remainingCount == 0 }
    public var totalCount: Int { remainingCount + doneCount }
}
