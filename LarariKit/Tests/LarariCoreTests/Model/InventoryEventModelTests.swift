import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("InventoryEvent model")
struct InventoryEventModelTests {
    let container: NSPersistentContainer
    var context: NSManagedObjectContext { container.viewContext }

    init() throws {
        container = try TestStack.makeContainer()
    }

    private func makeEvent() throws -> (Product, InventoryItem, InventoryEvent) {
        let space = Space(context: context)
        let product = Product(context: context)
        product.name = "Tej"
        product.space = space
        let item = InventoryItem(context: context)
        item.product = product
        item.quantity = 2
        let event = InventoryEvent(context: context)
        event.kind = .moved
        event.quantity = Decimal(string: "1.5")!
        event.unit = .liter
        event.fromLocationName = "Kamra"
        event.toLocationName = "Hűtő"
        event.occurredAt = .now
        event.product = product
        event.inventoryItem = item
        try context.save()
        return (product, item, event)
    }

    @Test func storesEveryField() throws {
        let (product, item, event) = try makeEvent()
        context.refresh(event, mergeChanges: false)
        #expect(event.kind == .moved)
        #expect(event.quantity == Decimal(string: "1.5")!)
        #expect(event.unit == .liter)
        #expect(event.fromLocationName == "Kamra" && event.toLocationName == "Hűtő")
        #expect(product.inventoryEventSet == [event])
        #expect(item.inventoryEventSet == [event])
    }

    @Test func unknownKindFallsBackToEdited() {
        let event = InventoryEvent(context: context)
        event.kindRaw = "teleported"
        #expect(event.kind == .edited)
    }

    @Test("Deleting a stock item keeps the product's history")
    func deletingItemKeepsEvents() throws {
        let (product, item, event) = try makeEvent()
        context.delete(item)
        try context.save()
        #expect(!event.isDeleted && event.managedObjectContext != nil)
        #expect(event.inventoryItem == nil)
        #expect(event.product == product)
    }

    @Test("Deleting the product removes its history")
    func deletingProductRemovesEvents() throws {
        let (product, _, _) = try makeEvent()
        context.delete(product)
        try context.save()
        #expect(try context.count(for: InventoryEvent.makeFetchRequest()) == 0)
    }
}
