import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Shopping undo actions")
struct ShoppingActionsTests {
    let stack: ShoppingTestStack
    var service: ShoppingService { stack.service }
    init() throws { stack = try ShoppingTestStack() }

    @Test func purchaseIsAppliedAtOnceAndSavedOnCommit() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "Kenyér")
        stack.now.advance(seconds: 30)

        let action = ShoppingActions.togglePurchased(item, service: service)
        #expect(item.isPurchased)
        #expect(item.purchasedAt == stack.now.date)
        #expect(stack.context.hasChanges)
        #expect(action.title == UndoTitle.purchased("Kenyér"))
        #expect(action.kind == .purchase)
        #expect(action.entityIDs == [item.publicId])

        try action.commit()
        #expect(!stack.context.hasChanges)
        #expect(item.isPurchased)
    }

    @Test func purchaseRevertRestoresEverything() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "Kenyér")
        let before = (item.updatedAt, item.updatedBy)
        stack.now.advance(seconds: 30)

        let action = ShoppingActions.togglePurchased(item, service: service)
        action.revert()

        #expect(!item.isPurchased)
        #expect(item.purchasedAt == nil)
        #expect(item.updatedAt == before.0)
        #expect(item.updatedBy == before.1)
        #expect(!stack.context.hasChanges)
    }

    @Test func unpurchaseRevertBringsThePurchaseDateBack() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "Kenyér")
        try service.togglePurchased(item)
        let purchasedAt = item.purchasedAt

        let action = ShoppingActions.togglePurchased(item, service: service)
        #expect(!item.isPurchased)
        #expect(action.title == UndoTitle.unpurchased("Kenyér"))
        action.revert()
        #expect(item.isPurchased)
        #expect(item.purchasedAt == purchasedAt)
    }

    @Test func deleteHidesUntilCommit() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "Kenyér")
        let pending = PendingDeletions()

        let action = ShoppingActions.deleteItem(item, service: service, pending: pending)
        #expect(pending.contains(item.publicId))
        #expect(action.title == UndoTitle.removed("Kenyér"))
        #expect(try service.items(in: list).count == 1)       // still in Core Data

        let id = item.publicId
        try action.commit()
        #expect(!pending.contains(id))
        #expect(try service.items(in: list).isEmpty)
        #expect(!stack.context.hasChanges)
    }

    @Test func deleteRevertOnlyUnhides() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "Kenyér")
        let pending = PendingDeletions()

        let action = ShoppingActions.deleteItem(item, service: service, pending: pending)
        action.revert()
        #expect(!pending.contains(item.publicId))
        #expect(try service.items(in: list) == [item])
        #expect(!stack.context.hasChanges)
    }

    @Test func actionsWorkThroughTheUndoQueue() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "Kenyér")
        let queue = UndoQueue(window: .seconds(3600))

        queue.enqueue(ShoppingActions.togglePurchased(item, service: service))
        #expect(queue.pending.count == 1)
        queue.undo(try #require(queue.pending.first).id)
        #expect(!item.isPurchased)
        #expect(queue.pending.isEmpty)

        queue.enqueue(ShoppingActions.togglePurchased(item, service: service))
        try queue.commitAll()
        #expect(item.isPurchased)
        #expect(!stack.context.hasChanges)
    }

    @Test func committingADeleteOfAnAlreadyDeletedItemIsHarmless() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "Kenyér")
        let pending = PendingDeletions()
        let action = ShoppingActions.deleteItem(item, service: service, pending: pending)
        try service.deleteList(list)                           // e.g. the list was deleted meanwhile
        try action.commit()
        #expect(try stack.count(ShoppingListItem.self) == 0)
    }
}
