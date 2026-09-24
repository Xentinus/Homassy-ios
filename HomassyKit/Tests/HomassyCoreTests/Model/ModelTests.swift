import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
struct ModelTests {
    let container: NSPersistentContainer
    var context: NSManagedObjectContext { container.viewContext }

    init() throws {
        container = try TestStack.makeContainer()
    }

    struct Graph {
        let space: Space
        let member: Member
        let product: Product
        let storage: StorageLocation
        let store: ShoppingLocation
        let item: InventoryItem
        let log: ConsumptionLog
        let list: ShoppingList
        let listItem: ShoppingListItem
    }

    private func makeGraph() throws -> Graph {
        let space = Space(context: context)
        space.name = "Otthon"
        space.kind = .household
        let member = Member(context: context)
        member.displayName = "Béla"
        member.space = space
        let product = Product(context: context)
        product.name = "Tej"
        product.space = space
        let storage = StorageLocation(context: context)
        storage.name = "Hűtő"
        storage.space = space
        let store = ShoppingLocation(context: context)
        store.name = "Spar"
        store.space = space
        let item = InventoryItem(context: context)
        item.quantity = 2
        item.product = product
        item.storageLocation = storage
        item.shoppingLocation = store
        let log = ConsumptionLog(context: context)
        log.quantity = 1
        log.remaining = 1
        log.inventoryItem = item
        let list = ShoppingList(context: context)
        list.name = "Heti"
        list.space = space
        let listItem = ShoppingListItem(context: context)
        listItem.shoppingList = list
        listItem.product = product
        listItem.shoppingLocation = store
        try context.save()
        return Graph(space: space, member: member, product: product, storage: storage, store: store,
                     item: item, log: log, list: list, listItem: listItem)
    }

    private func count<T: HomassyEntity>(_ type: T.Type) throws -> Int {
        try context.count(for: T.makeFetchRequest())
    }

    @Test func modelContainsExactlyTheTenEntities() {
        let names = Set(HomassyModel.shared.entities.compactMap(\.name))
        #expect(names == ["Space", "Member", "Product", "StorageLocation", "InventoryItem",
                          "ConsumptionLog", "InventoryEvent", "ShoppingLocation", "ShoppingList", "ShoppingListItem"])
    }

    @Test func sharedModelIsASingleInstance() {
        #expect(HomassyModel.shared === HomassyModel.shared)
    }

    @Test func entityClassesUseTheirPlainObjCNames() throws {
        let pairs: [(String, AnyClass)] = [
            ("Space", Space.self), ("Member", Member.self), ("Product", Product.self),
            ("StorageLocation", StorageLocation.self), ("InventoryItem", InventoryItem.self),
            ("ConsumptionLog", ConsumptionLog.self), ("InventoryEvent", InventoryEvent.self),
            ("ShoppingLocation", ShoppingLocation.self),
            ("ShoppingList", ShoppingList.self), ("ShoppingListItem", ShoppingListItem.self),
        ]
        for (name, type): (String, AnyClass) in pairs {
            let resolved: AnyClass = try #require(NSClassFromString(name), "no ObjC class named \(name)")
            #expect(ObjectIdentifier(resolved) == ObjectIdentifier(type), "\(name) resolves to another class")
            #expect(HomassyModel.shared.entitiesByName[name]?.managedObjectClassName == name)
        }
    }

    @Test func everyEntityInsertsAndSaves() throws {
        _ = try makeGraph()
        #expect(try count(Space.self) == 1)
        #expect(try count(Member.self) == 1)
        #expect(try count(Product.self) == 1)
        #expect(try count(StorageLocation.self) == 1)
        #expect(try count(ShoppingLocation.self) == 1)
        #expect(try count(InventoryItem.self) == 1)
        #expect(try count(ConsumptionLog.self) == 1)
        #expect(try count(ShoppingList.self) == 1)
        #expect(try count(ShoppingListItem.self) == 1)
    }

    @Test func insertAssignsPublicIdAndDates() {
        let before = Date.now.addingTimeInterval(-1)
        let first = Space(context: context)
        let second = Product(context: context)
        #expect(first.publicId != second.publicId)
        #expect(first.createdAt >= before)
        #expect(first.createdAt == first.updatedAt)
        #expect(first.createdBy == "")
        #expect(first.updatedBy == "")
    }

    @Test func attributeDefaults() {
        let space = Space(context: context)
        #expect(space.name == "")
        #expect(space.kind == .personal)
        #expect(space.sortOrder == 0)

        let product = Product(context: context)
        #expect(product.defaultUnit == .piece)
        #expect(product.isEatable)
        #expect(!product.isFavorite)
        #expect(product.image == nil)

        let item = InventoryItem(context: context)
        #expect(item.quantity == 0)
        #expect(item.unit == .piece)
        #expect(item.price == nil)
        #expect(!item.isFullyConsumed)

        let log = ConsumptionLog(context: context)
        #expect(log.quantity == 0)
        #expect(log.remaining == 0)

        let listItem = ShoppingListItem(context: context)
        #expect(listItem.quantity == 1)
        #expect(listItem.unit == .piece)
        #expect(!listItem.isPurchased)

        let storage = StorageLocation(context: context)
        #expect(!storage.isFreezer)

        let store = ShoppingLocation(context: context)
        #expect(store.latitude == nil)
        #expect(store.longitude == nil)
    }

    @Test func stampSetsCreatorOnceAndUpdaterEveryTime() {
        let space = Space(context: context)
        let first = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)

        space.stamp(by: "_owner", now: first)
        #expect(space.createdBy == "_owner")
        #expect(space.updatedBy == "_owner")
        #expect(space.createdAt == first)
        #expect(space.updatedAt == first)

        space.stamp(by: "_guest", now: later)
        #expect(space.createdBy == "_owner")
        #expect(space.createdAt == first)
        #expect(space.updatedBy == "_guest")
        #expect(space.updatedAt == later)
    }

    @Test func typedAccessorsRoundTripThroughTheStore() throws {
        let graph = try makeGraph()
        graph.space.kind = .personal
        graph.product.defaultUnit = .kilogram
        graph.item.unit = .liter
        graph.item.quantity = Decimal(string: "1.25")!
        graph.item.price = Decimal(string: "1299.90")!
        graph.store.latitude = 47.4979
        graph.store.longitude = 19.0402
        graph.listItem.unit = .pack
        try context.save()
        context.refreshAllObjects()

        #expect(graph.space.kindRaw == "personal")
        #expect(graph.product.defaultUnitRaw == "kilogram")
        #expect(graph.item.unitRaw == "liter")
        #expect(graph.item.quantity == Decimal(string: "1.25")!)
        #expect(graph.item.price == Decimal(string: "1299.90")!)
        #expect(graph.store.latitude == 47.4979)
        #expect(graph.store.longitude == 19.0402)
        #expect(graph.listItem.unit == .pack)

        graph.item.price = nil
        graph.store.latitude = nil
        #expect(graph.item.price == nil)
        #expect(graph.store.latitude == nil)
    }

    @Test func unknownRawValuesFallBack() {
        let space = Space(context: context)
        space.kindRaw = "castle"
        #expect(space.kind == .personal)
        let item = InventoryItem(context: context)
        item.unitRaw = "furlong"
        #expect(item.unit == .piece)
    }

    @Test func typedSetsMirrorRelationships() throws {
        let graph = try makeGraph()
        #expect(graph.space.productSet == [graph.product])
        #expect(graph.space.memberSet == [graph.member])
        #expect(graph.space.storageLocationSet == [graph.storage])
        #expect(graph.space.shoppingLocationSet == [graph.store])
        #expect(graph.space.shoppingListSet == [graph.list])
        #expect(graph.product.inventoryItemSet == [graph.item])
        #expect(graph.product.shoppingListItemSet == [graph.listItem])
        #expect(graph.item.consumptionLogSet == [graph.log])
        #expect(graph.list.itemSet == [graph.listItem])
        #expect(graph.storage.inventoryItemSet == [graph.item])
        #expect(graph.store.inventoryItemSet == [graph.item])
        #expect(graph.store.shoppingListItemSet == [graph.listItem])
    }

    @Test func deletingSpaceCascadesToEverything() throws {
        let graph = try makeGraph()
        context.delete(graph.space)
        try context.save()
        #expect(try count(Space.self) == 0)
        #expect(try count(Member.self) == 0)
        #expect(try count(Product.self) == 0)
        #expect(try count(StorageLocation.self) == 0)
        #expect(try count(ShoppingLocation.self) == 0)
        #expect(try count(InventoryItem.self) == 0)
        #expect(try count(ConsumptionLog.self) == 0)
        #expect(try count(ShoppingList.self) == 0)
        #expect(try count(ShoppingListItem.self) == 0)
    }

    @Test func deletingProductCascadesToItemsAndLogsAndNullifiesListItems() throws {
        let graph = try makeGraph()
        context.delete(graph.product)
        try context.save()
        #expect(try count(InventoryItem.self) == 0)
        #expect(try count(ConsumptionLog.self) == 0)
        #expect(try count(ShoppingListItem.self) == 1)
        #expect(graph.listItem.product == nil)
        #expect(try count(Space.self) == 1)
        #expect(graph.space.productSet.isEmpty)
    }

    @Test func deletingInventoryItemCascadesToLogs() throws {
        let graph = try makeGraph()
        context.delete(graph.item)
        try context.save()
        #expect(try count(ConsumptionLog.self) == 0)
        #expect(try count(Product.self) == 1)
        #expect(graph.storage.inventoryItemSet.isEmpty)
    }

    @Test func deletingShoppingListCascadesToItemsOnly() throws {
        let graph = try makeGraph()
        context.delete(graph.list)
        try context.save()
        #expect(try count(ShoppingListItem.self) == 0)
        #expect(try count(Product.self) == 1)
        #expect(graph.product.shoppingListItemSet.isEmpty)
    }

    @Test func deletingStorageLocationNullifiesItems() throws {
        let graph = try makeGraph()
        context.delete(graph.storage)
        try context.save()
        #expect(try count(InventoryItem.self) == 1)
        #expect(graph.item.storageLocation == nil)
    }

    @Test func deletingShoppingLocationNullifiesItemsAndListItems() throws {
        let graph = try makeGraph()
        context.delete(graph.store)
        try context.save()
        #expect(try count(InventoryItem.self) == 1)
        #expect(try count(ShoppingListItem.self) == 1)
        #expect(graph.item.shoppingLocation == nil)
        #expect(graph.listItem.shoppingLocation == nil)
    }

    @Test func deletingLeafObjectsNeverDeletesParents() throws {
        let graph = try makeGraph()
        context.delete(graph.member)
        context.delete(graph.log)
        context.delete(graph.listItem)
        try context.save()
        #expect(try count(Space.self) == 1)
        #expect(try count(InventoryItem.self) == 1)
        #expect(try count(ShoppingList.self) == 1)
        #expect(try count(Product.self) == 1)
    }
}
