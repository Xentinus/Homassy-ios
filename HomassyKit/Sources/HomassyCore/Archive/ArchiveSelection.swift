import Foundation

/// What the user chose to import from an archive: whole groups, and within a group optionally a subset.
public struct ArchiveSelection: Equatable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case products, stock, storageLocations, shoppingLocations, shoppingLists, members
    }

    public var groups: Set<Group>
    /// Per group, the records to import. A group without an entry imports all of them. Stock has no picks:
    /// it follows the imported products.
    public var picks: [Group: Set<UUID>]

    public init(groups: Set<Group>, productIDs: Set<UUID>? = nil, picks: [Group: Set<UUID>] = [:]) {
        self.groups = groups
        self.picks = picks
        if let productIDs { self.picks[.products] = productIDs }
    }

    /// The pick of `.products`; nil means all of them.
    public var productIDs: Set<UUID>? {
        get { picks[.products] }
        set { picks[.products] = newValue }
    }

    public static let everything = ArchiveSelection(groups: Set(Group.allCases))

    func keeps(_ id: UUID, in group: Group) -> Bool {
        groups.contains(group) && (picks[group]?.contains(id) ?? true)
    }
}

public struct ArchiveFilterResult: Equatable, Sendable {
    public let data: ArchiveData
    /// Records of groups the user left out that came along because an imported record references them.
    public let autoIncluded: [ArchiveEntity: Int]
    /// Shopping list items whose product is not imported; they arrive with the product's name instead.
    public let unlinkedListItems: Int

    /// True when nothing but the space itself would be imported.
    public var isEmpty: Bool {
        ArchiveEntity.allCases.allSatisfy { data.counts[$0] == 0 }
    }
}

extension ArchiveData {
    /// The part of the archive `selection` asks for, plus what it references (user rules, 2026-09-25):
    /// stock follows the imported products and brings its storage locations and stores, even unpicked ones;
    /// shopping lists bring their stores, and list items of products left out arrive without a product,
    /// named after it.
    /// The order of every collection is kept, and the result always passes `ArchiveValidator`.
    public func filtered(by selection: ArchiveSelection) -> ArchiveFilterResult {
        let groups = selection.groups
        let keptProducts = products.filter { selection.keeps($0.publicId, in: .products) }
        let productIDs = Set(keptProducts.map(\.publicId))

        let keptItems = groups.contains(.stock) ? inventoryItems.filter { productIDs.contains($0.product) } : []
        let itemIDs = Set(keptItems.map(\.publicId))
        let keptLogs = consumptionLogs.filter { itemIDs.contains($0.inventoryItem) }
        let keptEvents = groups.contains(.stock) ? inventoryEvents.filter { productIDs.contains($0.product) } : []

        let keptLists = shoppingLists.filter { selection.keeps($0.publicId, in: .shoppingLists) }
        let listIDs = Set(keptLists.map(\.publicId))
        let productNames = Dictionary(uniqueKeysWithValues: products.map { ($0.publicId, $0.name) })
        var unlinked = 0
        let keptListItems = shoppingListItems.filter { listIDs.contains($0.list) }.map { item -> ShoppingListItemDTO in
            guard let product = item.product, !productIDs.contains(product) else { return item }
            var copy = item
            copy.product = nil
            copy.customName = item.customName ?? productNames[product]
            unlinked += 1
            return copy
        }

        var autoIncluded: [ArchiveEntity: Int] = [:]
        func places<T: ArchiveRecord>(_ all: [T], group: ArchiveSelection.Group, entity: ArchiveEntity,
                                      referenced: Set<UUID>) -> [T] {
            var automatic = 0
            let kept = all.filter { record in
                if selection.keeps(record.publicId, in: group) { return true }
                guard referenced.contains(record.publicId) else { return false }
                automatic += 1
                return true
            }
            if automatic > 0 { autoIncluded[entity] = automatic }
            return kept
        }
        let keptStorage = places(storageLocations, group: .storageLocations, entity: .storageLocations,
                                 referenced: Set(keptItems.compactMap(\.storageLocation)))
        let keptStores = places(shoppingLocations, group: .shoppingLocations, entity: .shoppingLocations,
                                referenced: Set(keptItems.compactMap(\.shoppingLocation)
                                                + keptListItems.compactMap(\.shoppingLocation)))

        let data = ArchiveData(space: space,
                               members: members.filter { selection.keeps($0.publicId, in: .members) },
                               products: keptProducts,
                               storageLocations: keptStorage,
                               shoppingLocations: keptStores,
                               shoppingLists: keptLists,
                               inventoryItems: keptItems,
                               consumptionLogs: keptLogs,
                               inventoryEvents: keptEvents,
                               shoppingListItems: keptListItems)
        return ArchiveFilterResult(data: data, autoIncluded: autoIncluded, unlinkedListItems: unlinked)
    }
}
