import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("ShoppingActivityActions")
struct ShoppingActivityActionsTests {
    let stack: ShoppingTestStack
    init() throws { stack = try ShoppingTestStack() }

    func buy(_ ids: [UUID], shopping: ShoppingService? = nil) throws -> Int {
        try ShoppingActivityActions.purchase(itemIDs: ids, shopping: shopping ?? stack.service,
                                             inventory: stack.inventory, pending: stack.pending)
    }

    func stock() throws -> [InventoryItem] {
        try stack.context.fetch(NSFetchRequest<InventoryItem>(entityName: "InventoryItem"))
    }

    @Test func buysEveryMergedItemsWholeQuantityIntoTheUsualPlace() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let fridge = try stack.makeLocation("Hűtő")
        _ = try stack.inventory.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: nil, purchasedAt: nil,
                                         price: nil, currency: nil, storageLocation: fridge, shoppingLocation: nil)
        let spar = try stack.makeStore("Spar")
        let weekly = try stack.service.createList(name: "Heti", in: stack.space)
        let party = try stack.service.createList(name: "Buli", in: stack.space)
        let a = try stack.service.addItem(to: weekly, product: milk, quantity: 2, shoppingLocation: spar)
        let b = try stack.service.addItem(to: party, product: milk, quantity: 1, shoppingLocation: spar)
        stack.now.advance(seconds: 60)                         // the old stock and the new ones differ in createdAt

        #expect(try buy([a.publicId, b.publicId]) == 2)

        #expect(try stack.count(ShoppingListItem.self) == 0)                     // left both lists, saved
        let added = try stock().filter { $0.purchasedAt == stack.now.date }
        #expect(added.map(\.quantity).sorted() == [1, 2])
        #expect(added.allSatisfy { $0.storageLocation == fridge && $0.shoppingLocation == spar })
        #expect(added.allSatisfy { $0.expiresAt == nil })
        #expect(stack.pending.ids.isEmpty)
        #expect(!stack.context.hasChanges)
    }

    @Test func aNameOnlyItemGoesIntoInventoryAsANewProduct() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Szalvéta", quantity: 2)
        #expect(try buy([item.publicId]) == 1)
        #expect(try stack.count(ShoppingListItem.self) == 0)
        #expect(try stock().map { $0.product?.name } == ["Szalvéta"])
    }

    @Test func goneBoughtAndPendingItemsAreSkipped() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let bought = try stack.service.addItem(to: list, customName: "Tej")
        try stack.service.togglePurchased(bought)
        let hidden = try stack.service.addItem(to: list, customName: "Vaj")
        stack.pending.hide(hidden.publicId)
        #expect(try buy([UUID(), bought.publicId, hidden.publicId]) == 0)
        #expect(try stock().isEmpty)
    }

    @Test func aReadOnlyHouseholdBuysNothing() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Tej")
        let readOnly = ShoppingService(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user,
                                       canEdit: { _ in false })
        #expect(throws: ServiceError.readOnlySpace) { _ = try buy([item.publicId], shopping: readOnly) }
        #expect(try stack.count(ShoppingListItem.self) == 1)
    }
}
