import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("InventoryActions")
struct InventoryActionsTests {
    @Test func consumeStaysInMemoryUntilCommit() async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Eggs"), 3)
        let service = env.inventoryService()
        let action = try InventoryActions.consume(item, quantity: 1, service: service)
        #expect(action.title == UndoTitle.consumed("Eggs"))
        #expect(item.quantity == 2)
        #expect(env.context.hasChanges)
        #expect(try service.logs(for: item).count == 1)

        try action.commit()
        #expect(!env.context.hasChanges)
        env.context.refresh(item, mergeChanges: false)
        #expect(item.quantity == 2)
        #expect(try env.count(ConsumptionLog.self) == 1)
    }

    @Test func revertRestoresQuantityAndRemovesTheLog() async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Eggs"), 3)
        let updatedAt = item.updatedAt
        let action = try InventoryActions.consume(item, quantity: 1, service: env.inventoryService())
        action.revert()
        #expect(item.quantity == 3)
        #expect(item.updatedAt == updatedAt)
        #expect(try env.count(ConsumptionLog.self) == 0)
        #expect(!env.context.hasChanges)
    }

    @Test("Revert is still correct after another save flushed the change")
    func revertAfterEarlySave() async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Milk", unit: .liter), 2)
        let action = try InventoryActions.consume(item, quantity: 2, service: env.inventoryService())
        try env.context.save()                                  // e.g. another action committed
        #expect(item.isFullyConsumed)

        action.revert()
        #expect(!env.context.hasChanges)
        env.context.refresh(item, mergeChanges: false)
        #expect(item.quantity == 2)
        #expect(!item.isFullyConsumed && item.consumedAt == nil)
        #expect(try env.count(ConsumptionLog.self) == 0)
    }

    @Test func markUsedUpRevert() async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Rice", unit: .kilogram), 1)
        let action = try InventoryActions.markUsedUp(item, service: env.inventoryService())
        #expect(action.title == UndoTitle.usedUp("Rice"))
        #expect(item.isFullyConsumed)
        action.revert()
        #expect(!item.isFullyConsumed && item.consumedAt == nil && item.quantity == 1)
        #expect(try env.count(ConsumptionLog.self) == 0)
    }

    @Test func moveRevertRestoresTheOldLocation() async throws {
        let env = try ServiceTestEnvironment()
        let storage = env.storageService()
        let fridge = try storage.create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let freezer = try storage.create(in: env.personal, name: "Freezer", color: nil, isFreezer: true)
        let item = try env.stock(try await env.makeProduct("Peas"), 1, location: fridge)
        let action = try InventoryActions.move(item, to: freezer, service: env.inventoryService())
        #expect(action.title == UndoTitle.moved("Peas"))
        #expect(item.storageLocation == freezer)
        action.revert()
        #expect(item.storageLocation == fridge)
        #expect(!env.context.hasChanges)

        let again = try InventoryActions.move(item, to: freezer, service: env.inventoryService())
        try again.commit()
        env.context.refresh(item, mergeChanges: false)
        #expect(item.storageLocation == freezer)
    }

    @Test func deleteHidesThenDeletesOnCommit() async throws {
        let env = try ServiceTestEnvironment()
        let service = env.inventoryService()
        let item = try env.stock(try await env.makeProduct("Bread"), 1)
        try service.consume(item, quantity: Decimal(string: "0.5")!)
        let pending = PendingDeletions()

        let undo = try InventoryActions.delete(item, service: service, pending: pending)
        #expect(pending.contains(item.publicId))
        #expect(!env.context.hasChanges)
        undo.revert()
        #expect(!pending.contains(item.publicId))

        let commit = try InventoryActions.delete(item, service: service, pending: pending)
        try commit.commit()
        #expect(try env.count(InventoryItem.self) == 0)
        #expect(try env.count(ConsumptionLog.self) == 0)
        #expect(pending.ids.isEmpty)
    }

    @Test func revertAfterRemoteDeletionDoesNotCrash() async throws {
        let env = try ServiceTestEnvironment()
        let item = try env.stock(try await env.makeProduct("Eggs"), 3)
        let action = try InventoryActions.consume(item, quantity: 1, service: env.inventoryService())
        try env.context.save()
        env.context.delete(item)
        try env.context.save()
        action.revert()
        #expect(!env.context.hasChanges)
    }

    @Test func titlesAreTranslated() {
        for key in ["undo.item.consume %@", "undo.item.usedUp %@", "undo.item.move %@"] {
            for id in ["hu_HU", "en_US", "de_DE"] {
                #expect(CoreLocalization.lookup(key, locale: Locale(identifier: id)) != nil, "\(key) \(id)")
            }
        }
    }

    @Test func containerExposesInventory() throws {
        let env = try ServiceTestEnvironment()
        let services = ServiceContainer(spaceStore: env.spaceStore, context: env.context, userRecordName: ServiceTestEnvironment.user)
        #expect(services.inventory.context === env.context)
    }
}
