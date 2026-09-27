import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Shopping purchase")
struct ShoppingPurchaseTests {
    let stack: ShoppingTestStack
    var shopping: ShoppingService { stack.service }
    var inventory: InventoryService { stack.inventory }
    var pending: PendingDeletions { stack.pending }
    init() throws { stack = try ShoppingTestStack() }

    private func buy(_ item: ShoppingListItem, _ details: PurchaseDetails,
                     shopping: ShoppingService? = nil) throws -> UndoableAction {
        try ShoppingPurchase.purchase(item, details: details, shopping: shopping ?? self.shopping,
                                      inventory: inventory, pending: pending)
    }

    private func stock() throws -> [InventoryItem] {
        try stack.context.fetch(NSFetchRequest<InventoryItem>(entityName: "InventoryItem"))
    }

    @Test func fullPurchaseAddsStockAndHidesTheItem() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        let fridge = try stack.makeLocation("Hűtő")
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: milk, quantity: 2)
        stack.now.advance(seconds: 60)

        let action = try buy(item, PurchaseDetails(quantity: 2, storeID: spar.publicId, price: 459, currency: "HUF",
                                                   lots: [LotDetails(quantity: 2, storageLocationID: fridge.publicId)]))
        let added = try #require(try stock().first)
        #expect(added.product == milk)
        #expect(added.quantity == 2)
        #expect(added.unit == .liter)
        #expect(added.shoppingLocation == spar)
        #expect(added.storageLocation == fridge)
        #expect(added.purchasedAt == stack.now.date)
        #expect(added.price == 459)
        #expect(added.currency == "HUF")
        #expect(pending.contains(item.publicId))
        #expect(stack.context.hasChanges)
        #expect(action.title == UndoTitle.purchased("Tej"))
        #expect(action.kind == .purchase)
    }

    @Test func commitDeletesTheItemAndSaves() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: try stack.makeProduct("Tej"))
        let id = item.publicId
        let action = try buy(item, PurchaseDetails(quantity: 1))
        try action.commit()
        #expect(try shopping.items(in: list).isEmpty)
        #expect(try stack.count(InventoryItem.self) == 1)
        #expect(!pending.contains(id))
        #expect(!stack.context.hasChanges)
    }

    @Test func partialPurchaseKeepsTheRemainder() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: try stack.makeProduct("Tej", unit: .liter), quantity: 2)
        let action = try buy(item, PurchaseDetails(quantity: Decimal(string: "0.5")!, keepRemainder: true))
        #expect(item.quantity == Decimal(string: "1.5")!)
        #expect(!pending.contains(item.publicId))
        try action.commit()
        #expect(try shopping.items(in: list) == [item])
        #expect(try stock().first?.quantity == Decimal(string: "0.5")!)
    }

    @Test func partialPurchaseWithoutKeepingRemovesTheItem() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: try stack.makeProduct("Tej"), quantity: 2)
        try buy(item, PurchaseDetails(quantity: 1, keepRemainder: false)).commit()
        #expect(try shopping.items(in: list).isEmpty)
        #expect(try stock().first?.quantity == 1)
    }

    @Test func buyingMoreThanListedRemovesTheItem() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: try stack.makeProduct("Tej"), quantity: 2)
        try buy(item, PurchaseDetails(quantity: 3, keepRemainder: true)).commit()
        #expect(try shopping.items(in: list).isEmpty)
        #expect(try stock().first?.quantity == 3)
    }

    @Test func customItemMatchesAnExistingProductByName() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, customName: "tej")
        try buy(item, PurchaseDetails(quantity: 1)).commit()
        #expect(try stock().first?.product == milk)
        #expect(try stack.count(Product.self) == 1)
    }

    @Test func customItemCreatesAProduct() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, customName: "Szalvéta", unit: .pack)
        try buy(item, PurchaseDetails(quantity: 1)).commit()
        let product = try #require(try stock().first?.product)
        #expect(product.name == "Szalvéta")
        #expect(product.defaultUnit == .pack)
        #expect(product.space == stack.space)
        #expect(product.createdBy == stack.user)
    }

    @Test func revertUndoesEverything() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, customName: "Szalvéta", quantity: 2)
        let before = (item.updatedAt, item.updatedBy)
        stack.now.advance(seconds: 60)

        let action = try buy(item, PurchaseDetails(quantity: 1, keepRemainder: true))
        #expect(item.quantity == 1)
        action.revert()

        #expect(try stack.count(InventoryItem.self) == 0)
        #expect(try stack.count(InventoryEvent.self) == 0)
        #expect(try stack.count(PurchaseRecord.self) == 0)
        #expect(try stack.count(Product.self) == 0)
        #expect(item.quantity == 2)
        #expect(item.updatedAt == before.0)
        #expect(item.updatedBy == before.1)
        #expect(!pending.contains(item.publicId))
        #expect(!stack.context.hasChanges)
    }

    @Test func revertOfAFullPurchaseShowsTheItemAgain() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: try stack.makeProduct("Tej"))
        let action = try buy(item, PurchaseDetails(quantity: 1))
        action.revert()
        #expect(!pending.contains(item.publicId))
        #expect(try shopping.items(in: list) == [item])
        #expect(try stack.count(Product.self) == 1)          // an existing product is kept
        #expect(!stack.context.hasChanges)
    }

    @Test func validationWritesNothing() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, customName: "Szalvéta")
        let other = try stack.makeOtherSpace()
        let foreignStore = try stack.makeStore("Idegen", in: other)
        let foreignLocation = try stack.makeLocation("Idegen", in: other)
        let readOnly = ShoppingService(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user,
                                       canEdit: { _ in false })

        #expect(throws: ServiceError.quantityMustBePositive) { _ = try buy(item, PurchaseDetails(quantity: 0)) }
        #expect(throws: ServiceError.notFound) {
            _ = try buy(item, PurchaseDetails(quantity: 1, storeID: foreignStore.publicId))
        }
        #expect(throws: ServiceError.notFound) {
            _ = try buy(item, PurchaseDetails(quantity: 1, lots: [LotDetails(quantity: 1, storageLocationID: foreignLocation.publicId)]))
        }
        #expect(throws: ServiceError.expiryBeforePurchase) {
            _ = try buy(item, PurchaseDetails(quantity: 1, lots: [LotDetails(quantity: 1, expiresAt: stack.now.date.addingTimeInterval(-3 * 86_400))]))
        }
        #expect(throws: ServiceError.readOnlySpace) {
            _ = try buy(item, PurchaseDetails(quantity: 1), shopping: readOnly)
        }
        #expect(try stack.count(InventoryItem.self) == 0)
        #expect(try stack.count(Product.self) == 0)
        #expect(item.quantity == 1)
        #expect(!pending.contains(item.publicId))
        #expect(!stack.context.hasChanges)
    }

    @Test func twoLotsBecomeTwoItemsAndUndoRemovesBoth() throws {
        let milk = try stack.makeProduct("Tej")
        let fridge = try stack.makeLocation("Hűtő")
        let garage = try stack.makeLocation("Garázs")
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: milk, quantity: 3)
        let action = try buy(item, PurchaseDetails(quantity: 2, price: 900, lots: [
            LotDetails(quantity: 1, storageLocationID: fridge.publicId),
            LotDetails(quantity: 1, storageLocationID: garage.publicId)]))
        let added = try stock().sorted { ($0.storageLocation?.name ?? "") < ($1.storageLocation?.name ?? "") }
        #expect(added.map(\.storageLocation) == [garage, fridge])
        #expect(added.map(\.price) == [450, 450])
        #expect(item.quantity == 1, "the remainder stays on the list")
        #expect(try stack.count(PurchaseRecord.self) == 2)
        action.revert()
        #expect(try stock().isEmpty)
        #expect(try stack.count(PurchaseRecord.self) == 0)
        #expect(try stack.count(InventoryEvent.self) == 0)
        #expect(item.quantity == 3)
    }

    @Test func aBadSecondLotOfACustomItemWritesNothing() throws {
        let fridge = try stack.makeLocation("Hűtő")
        let foreignLocation = try stack.makeLocation("Idegen", in: try stack.makeOtherSpace())
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, customName: "Szalvéta", quantity: 2)
        #expect(throws: ServiceError.notFound) {
            _ = try buy(item, PurchaseDetails(quantity: 2, lots: [
                LotDetails(quantity: 1, storageLocationID: fridge.publicId),
                LotDetails(quantity: 1, storageLocationID: foreignLocation.publicId)]))
        }
        #expect(try stack.count(Product.self) == 0)
        #expect(try stack.count(InventoryItem.self) == 0)
        #expect(!stack.context.hasChanges)
    }

    @Test func theLotsSumIsTheBoughtAmount() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: try stack.makeProduct("Tej"), quantity: 5)
        _ = try buy(item, PurchaseDetails(quantity: 99, lots: [LotDetails(quantity: 1), LotDetails(quantity: 2)]))
        #expect(item.quantity == 2)
        #expect(try stock().map(\.quantity).reduce(0, +) == 3)
    }

    @Test func defaultStorageLocationIsTheLastOneUsed() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let pantry = try stack.makeLocation("Kamra")
        let fridge = try stack.makeLocation("Hűtő")
        try inventory.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: nil, purchasedAt: nil, price: nil,
                               currency: nil, storageLocation: pantry, shoppingLocation: nil)
        try inventory.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: nil, purchasedAt: nil, price: nil,
                               currency: nil, storageLocation: fridge, shoppingLocation: nil)
        #expect(ShoppingPurchase.defaultStorageLocation(for: milk, inventory: inventory) == fridge)
        #expect(ShoppingPurchase.defaultStorageLocation(for: nil, inventory: inventory) == nil)
    }

    @Test func withoutInventoryTheItemOnlyLeavesTheList() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, customName: "Szalvéta", quantity: 2)
        let foreignStore = try stack.makeStore("Idegen", in: try stack.makeOtherSpace())

        // The store and inventory fields are ignored, so a foreign store does not matter.
        let action = try buy(item, PurchaseDetails(quantity: 2, storeID: foreignStore.publicId, addToInventory: false))
        #expect(pending.contains(item.publicId))
        try action.commit()
        #expect(try shopping.items(in: list).isEmpty)
        #expect(try stack.count(InventoryItem.self) == 0)
        #expect(try stack.count(Product.self) == 0)
    }

    @Test func withoutInventoryARemainderStays() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, customName: "Szalvéta", quantity: 3)
        let action = try buy(item, PurchaseDetails(quantity: 1, keepRemainder: true, addToInventory: false))
        #expect(item.quantity == 2)
        action.revert()
        #expect(item.quantity == 3)
        #expect(try stack.count(InventoryItem.self) == 0)
        #expect(!stack.context.hasChanges)
    }

    @Test func purchaseThroughTheUndoQueue() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, customName: "Szalvéta")
        let queue = UndoQueue(window: .seconds(3600))
        queue.enqueue(try buy(item, PurchaseDetails(quantity: 1)))
        queue.undo(try #require(queue.pending.first).id)
        #expect(try stack.count(InventoryItem.self) == 0)
        #expect(try shopping.items(in: list) == [item])

        queue.enqueue(try buy(item, PurchaseDetails(quantity: 1)))
        try queue.commitAll()
        #expect(try shopping.items(in: list).isEmpty)
        #expect(try stack.count(InventoryItem.self) == 1)
        #expect(!stack.context.hasChanges)
    }

    @Test func withInventoryThePurchaseIsRecordedAndUndoRemovesIt() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: milk, quantity: 2)
        let action = try buy(item, PurchaseDetails(quantity: 2, storeID: spar.publicId, price: 900))
        let record = try #require(try stack.context.fetch(NSFetchRequest<PurchaseRecord>(entityName: "PurchaseRecord")).first)
        #expect(record.inventoryItem != nil)
        #expect(record.price == 900)
        #expect(record.shoppingLocation == spar)
        action.revert()
        #expect(try stack.count(PurchaseRecord.self) == 0)
    }

    @Test func withoutInventoryAProductPurchaseIsStillRecorded() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, product: milk, quantity: 2)
        stack.now.advance(seconds: 60)

        let action = try buy(item, PurchaseDetails(quantity: 2, storeID: spar.publicId, price: 900, currency: "HUF",
                                                   addToInventory: false))
        let record = try #require(try stack.context.fetch(NSFetchRequest<PurchaseRecord>(entityName: "PurchaseRecord")).first)
        #expect(record.product == milk)
        #expect(record.quantity == 2)
        #expect(record.unit == .liter)
        #expect(record.price == 900)
        #expect(record.shoppingLocation == spar)
        #expect(record.inventoryItem == nil)
        #expect(record.purchasedAt == stack.now.date)
        #expect(try stack.count(InventoryItem.self) == 0)

        action.revert()
        #expect(try stack.count(PurchaseRecord.self) == 0)
        #expect(!stack.context.hasChanges)

        try buy(item, PurchaseDetails(quantity: 2, price: 900, addToInventory: false)).commit()
        #expect(try stack.count(PurchaseRecord.self) == 1)
        #expect(!stack.context.hasChanges)
    }

    @Test func withoutInventoryACustomItemRecordsNothing() throws {
        let list = try shopping.createList(name: "Heti", in: stack.space)
        let item = try shopping.addItem(to: list, customName: "Szalvéta")
        try buy(item, PurchaseDetails(quantity: 1, price: 300, addToInventory: false)).commit()
        #expect(try stack.count(PurchaseRecord.self) == 0)
        #expect(try stack.count(Product.self) == 0)
    }
}
