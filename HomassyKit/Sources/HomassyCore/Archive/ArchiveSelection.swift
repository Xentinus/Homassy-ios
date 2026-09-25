import Foundation

/// What the user chose to import from an archive: whole groups, and optionally a subset of the products.
public struct ArchiveSelection: Equatable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case products, stock, storageLocations, shoppingLocations, shoppingLists, members
    }

    public var groups: Set<Group>
    /// The products to import when `groups` contains `.products`; nil means all of them.
    public var productIDs: Set<UUID>?

    public init(groups: Set<Group>, productIDs: Set<UUID>? = nil) {
        self.groups = groups
        self.productIDs = productIDs
    }

    public static let everything = ArchiveSelection(groups: Set(Group.allCases))
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
    /// stock follows the imported products and brings its storage locations and stores; shopping lists
    /// bring their stores, and list items of products left out arrive without a product, named after it.
    /// The order of every collection is kept, and the result always passes `ArchiveValidator`.
    public func filtered(by selection: ArchiveSelection) -> ArchiveFilterResult {
        let groups = selection.groups
        let keptProducts = groups.contains(.products)
            ? products.filter { selection.productIDs?.contains($0.publicId) ?? true }
            : []
        let productIDs = Set(keptProducts.map(\.publicId))

        let keptItems = groups.contains(.stock) ? inventoryItems.filter { productIDs.contains($0.product) } : []
        let itemIDs = Set(keptItems.map(\.publicId))
        let keptLogs = consumptionLogs.filter { itemIDs.contains($0.inventoryItem) }
        let keptEvents = groups.contains(.stock) ? inventoryEvents.filter { productIDs.contains($0.product) } : []

        let keptLists = groups.contains(.shoppingLists) ? shoppingLists : []
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
            if groups.contains(group) { return all }
            let kept = all.filter { referenced.contains($0.publicId) }
            if !kept.isEmpty { autoIncluded[entity] = kept.count }
            return kept
        }
        let keptStorage = places(storageLocations, group: .storageLocations, entity: .storageLocations,
                                 referenced: Set(keptItems.compactMap(\.storageLocation)))
        let keptStores = places(shoppingLocations, group: .shoppingLocations, entity: .shoppingLocations,
                                referenced: Set(keptItems.compactMap(\.shoppingLocation)
                                                + keptListItems.compactMap(\.shoppingLocation)))

        let data = ArchiveData(space: space,
                               members: groups.contains(.members) ? members : [],
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
