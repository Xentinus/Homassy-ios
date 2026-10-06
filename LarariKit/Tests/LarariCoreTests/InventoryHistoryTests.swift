import CoreData
import Foundation
import Testing
@testable import LarariCore

/// Every stock action writes one `InventoryEvent`; undo removes it again (README "Inventory history").
@MainActor
@Suite("Inventory history and partial moves")
struct InventoryHistoryTests {
    static func d(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    func locations(_ env: ServiceTestEnvironment) throws -> (pantry: StorageLocation, fridge: StorageLocation) {
        let storage = env.storageService()
        return (try storage.create(in: env.personal, name: "Pantry", color: nil, isFreezer: false),
                try storage.create(in: env.personal, name: "Fridge", color: nil, isFreezer: false))
    }

    func kinds(_ service: InventoryService, _ product: Product) throws -> [InventoryEventKind] {
        try service.events(for: product).map(\.kind)
    }

    @Test func addStockRecordsAnAddedEvent() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, _) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 12, location: pantry)
        let event = try #require(try env.inventoryService().events(for: eggs).first)
        #expect(event.kind == .added)
        #expect(event.quantity == 12 && event.unit == .piece)
        #expect(event.toLocationName == "Pantry" && event.fromLocationName == nil)
        #expect(event.inventoryItem == item && event.product == eggs)
        #expect(event.occurredAt == ServiceTestEnvironment.fixedNow)
        #expect(event.createdBy == ServiceTestEnvironment.user)
    }

    @Test func everyActionRecordsItsEventNewestFirst() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge) = try locations(env)
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let item = try env.stock(milk, 3, location: pantry)
        let service = env.inventoryService(user: ServiceTestEnvironment.otherUser)
        try service.consume(item, quantity: 1)
        try service.move(item, to: fridge)
        try service.update(item, quantity: 4, unit: .liter, expiresAt: nil, purchasedAt: nil,
                           price: nil, currency: nil, storageLocation: fridge)
        try service.markUsedUp(item)
        #expect(try kinds(service, milk) == [.consumed, .edited, .moved, .consumed, .added])

        let events = try service.events(for: milk)
        #expect(events[0].quantity == 4)                                   // used up the remaining 4
        #expect(events[2].fromLocationName == "Pantry" && events[2].toLocationName == "Fridge")
        #expect(events[3].quantity == 1 && events[3].fromLocationName == "Pantry")
        #expect(events.dropLast().allSatisfy { $0.createdBy == ServiceTestEnvironment.otherUser })
        #expect(!env.context.hasChanges)
    }

    @Test("Deleting a stock item records it and keeps the history")
    func deleteKeepsHistory() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, _) = try locations(env)
        let bread = try await env.makeProduct("Bread")
        let item = try env.stock(bread, 2, location: pantry)
        let service = env.inventoryService()
        try service.delete(item)
        let events = try service.events(for: bread)
        #expect(events.map(\.kind) == [.deleted, .added])
        #expect(events[0].quantity == 2 && events[0].fromLocationName == "Pantry")
        #expect(events.allSatisfy { $0.inventoryItem == nil })
    }

    @Test func movingToTheSameLocationRecordsNothing() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, _) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 12, location: pantry)
        let service = env.inventoryService()
        try service.move(item, to: pantry)
        #expect(try service.move(item, quantity: 4, to: pantry) == item)
        #expect(try kinds(service, eggs) == [.added])
    }

    @Test("A partial move splits the item: the moved part keeps dates and price")
    func partialMoveSplits() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        let service = env.inventoryService()
        let item = try service.addStock(product: eggs, quantity: 12, unit: .piece, expiresAt: env.day(10),
                                        purchasedAt: env.day(-1), price: 990, currency: "HUF",
                                        storageLocation: pantry, shoppingLocation: nil)
        try service.consume(item, quantity: 2)

        let moved = try service.move(item, quantity: 4, to: fridge)
        #expect(moved != item)
        #expect(item.quantity == 6 && item.storageLocation == pantry)
        #expect(moved.quantity == 4 && moved.storageLocation == fridge && moved.product == eggs)
        #expect(moved.unit == .piece && moved.expiresAt == env.day(10) && moved.purchasedAt == env.day(-1))
        #expect(moved.price == 990 && moved.currency == "HUF")
        #expect(try service.logs(for: moved).isEmpty)
        #expect(try service.logs(for: item).count == 1)

        let event = try #require(try service.events(for: eggs).first)
        #expect(event.kind == .moved && event.quantity == 4)
        #expect(event.fromLocationName == "Pantry" && event.toLocationName == "Fridge")
        #expect(event.inventoryItem == moved)
        #expect(Set(try service.items(for: eggs)) == [item, moved])
        #expect(!env.context.hasChanges)
    }

    @Test func movingTheWholeAmountMovesTheItemItself() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge) = try locations(env)
        let item = try env.stock(try await env.makeProduct("Eggs"), 6, location: pantry)
        let moved = try env.inventoryService().move(item, quantity: 6, to: fridge)
        #expect(moved == item && item.storageLocation == fridge)
        #expect(try env.count(InventoryItem.self) == 1)
    }

    @Test("Partial move amounts are limited to what is in stock", arguments: [("0", "positive"), ("-1", "positive"), ("6.5", "exceeds")])
    func partialMoveLimits(amount: String, expected: String) async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge) = try locations(env)
        let item = try env.stock(try await env.makeProduct("Eggs"), 6, location: pantry)
        let error: ServiceError = expected == "positive" ? .quantityMustBePositive : .quantityExceedsStock
        #expect(throws: error) { try env.inventoryService().move(item, quantity: Self.d(amount), to: fridge) }
        #expect(item.quantity == 6 && item.storageLocation == pantry)
        #expect(try env.count(InventoryItem.self) == 1)
    }

    @Test func transferRecordsAnAddedEventInTheTargetSpace() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let item = try env.stock(try await env.makeProduct("Milk"), 2)
        let service = env.inventoryService()
        let moved = try service.transfer(item, to: home)
        let product = try #require(moved.product)
        let event = try #require(try service.events(for: product).first)
        #expect(event.kind == .added && event.quantity == 2 && event.inventoryItem == moved)
    }

    // MARK: Undo

    @Test func undoingAConsumeRemovesItsEvent() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 3)
        let service = env.inventoryService()
        let action = try InventoryActions.consume(item, quantity: 1, service: service)
        #expect(try kinds(service, eggs) == [.consumed, .added])
        action.revert()
        #expect(try kinds(service, eggs) == [.added])
        #expect(!env.context.hasChanges)
    }

    @Test func undoingAPartialMoveMergesTheItemBack() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 12, location: pantry)
        let service = env.inventoryService()
        let action = try InventoryActions.move(item, quantity: 5, to: fridge, service: service)
        #expect(action.title == UndoTitle.moved("Eggs") && action.kind == .move)
        #expect(item.quantity == 7)
        #expect(try env.count(InventoryItem.self) == 2)

        action.revert()
        #expect(item.quantity == 12 && item.storageLocation == pantry)
        #expect(try env.count(InventoryItem.self) == 1)
        #expect(try kinds(service, eggs) == [.added])
        #expect(!env.context.hasChanges)
    }

    @Test func committingAPartialMoveKeepsBothItems() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge) = try locations(env)
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 12, location: pantry)
        let service = env.inventoryService()
        try InventoryActions.move(item, quantity: 5, to: fridge, service: service).commit()
        #expect(!env.context.hasChanges)
        #expect(try service.items(for: eggs).map(\.quantity).sorted() == [5, 7])
        #expect(try kinds(service, eggs) == [.moved, .added])
    }

    @Test func quantityExceedsStockIsTranslated() {
        for id in ["hu_HU", "en_US", "de_DE"] {
            #expect(CoreLocalization.lookup("error.quantityExceedsStock", locale: Locale(identifier: id)) != nil)
        }
    }
}
