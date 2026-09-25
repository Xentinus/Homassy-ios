import Foundation

/// Structural checks that need the whole archive. Runs before anything is written.
enum ArchiveValidator {
    static func validate(_ data: ArchiveData) throws {
        var seen: Set<UUID> = [data.space.publicId]
        func unique(_ ids: [UUID]) throws {
            for id in ids where !seen.insert(id).inserted {
                throw ArchiveError.duplicatePublicId(id)
            }
        }
        try unique(data.members.map(\.publicId))
        try unique(data.products.map(\.publicId))
        try unique(data.storageLocations.map(\.publicId))
        try unique(data.shoppingLocations.map(\.publicId))
        try unique(data.shoppingLists.map(\.publicId))
        try unique(data.inventoryItems.map(\.publicId))
        try unique(data.consumptionLogs.map(\.publicId))
        try unique(data.inventoryEvents.map(\.publicId))
        try unique(data.shoppingListItems.map(\.publicId))

        let products = Set(data.products.map(\.publicId))
        let storage = Set(data.storageLocations.map(\.publicId))
        let stores = Set(data.shoppingLocations.map(\.publicId))
        let lists = Set(data.shoppingLists.map(\.publicId))
        let items = Set(data.inventoryItems.map(\.publicId))

        func check(_ id: UUID?, in set: Set<UUID>, entity: ArchiveEntity, record: UUID, field: String) throws {
            guard let id else { return }
            guard set.contains(id) else {
                throw ArchiveError.brokenReference(entity: entity, publicId: record, field: field)
            }
        }
        for item in data.inventoryItems {
            try check(item.product, in: products, entity: .inventoryItems, record: item.publicId, field: "product")
            try check(item.storageLocation, in: storage, entity: .inventoryItems, record: item.publicId, field: "storageLocation")
            try check(item.shoppingLocation, in: stores, entity: .inventoryItems, record: item.publicId, field: "shoppingLocation")
        }
        for log in data.consumptionLogs {
            try check(log.inventoryItem, in: items, entity: .consumptionLogs, record: log.publicId, field: "inventoryItem")
        }
        for event in data.inventoryEvents {
            try check(event.product, in: products, entity: .inventoryEvents, record: event.publicId, field: "product")
            try check(event.inventoryItem, in: items, entity: .inventoryEvents, record: event.publicId, field: "inventoryItem")
        }
        for item in data.shoppingListItems {
            try check(item.list, in: lists, entity: .shoppingListItems, record: item.publicId, field: "list")
            try check(item.product, in: products, entity: .shoppingListItems, record: item.publicId, field: "product")
            try check(item.shoppingLocation, in: stores, entity: .shoppingListItems, record: item.publicId, field: "shoppingLocation")
        }
    }
}
