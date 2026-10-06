import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Shopping delete action")
struct ShoppingActionsTests {
    let stack: ShoppingTestStack
    var service: ShoppingService { stack.service }
    init() throws { stack = try ShoppingTestStack() }

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
