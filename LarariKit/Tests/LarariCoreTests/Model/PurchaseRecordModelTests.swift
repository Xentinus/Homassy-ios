import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("PurchaseRecord model")
struct PurchaseRecordModelTests {
    let container: NSPersistentContainer
    var context: NSManagedObjectContext { container.viewContext }

    init() throws {
        container = try TestStack.makeContainer()
    }

    private func makeRecord() throws -> (Product, ShoppingLocation, InventoryItem, PurchaseRecord) {
        let space = Space(context: context)
        let product = Product(context: context)
        product.name = "Tej"
        product.space = space
        let store = ShoppingLocation(context: context)
        store.name = "Spar"
        store.space = space
        let item = InventoryItem(context: context)
        item.product = product
        let record = PurchaseRecord(context: context)
        record.product = product
        record.shoppingLocation = store
        record.inventoryItem = item
        record.quantity = 2
        record.unit = .liter
        record.price = Decimal(string: "899.9")!
        record.currency = "HUF"
        record.purchasedAt = Date(timeIntervalSince1970: 1_790_000_000)
        try context.save()
        return (product, store, item, record)
    }

    @Test func storesEveryField() throws {
        let (product, store, item, record) = try makeRecord()
        context.refresh(record, mergeChanges: false)
        #expect(record.quantity == 2)
        #expect(record.unit == .liter)
        #expect(record.price == Decimal(string: "899.9")!)
        #expect(record.currency == "HUF")
        #expect(record.purchasedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(record.product == product)
        #expect(record.shoppingLocation == store)
        #expect(record.inventoryItem == item)
        #expect(product.purchaseRecordSet == [record])
        #expect(store.purchaseRecordSet == [record])
        #expect(item.purchaseRecordSet == [record])
    }

    @Test func deletingTheStockOrTheStoreKeepsTheRecord() throws {
        let (_, store, item, record) = try makeRecord()
        context.delete(item)
        context.delete(store)
        try context.save()
        #expect(!record.isDeleted)
        #expect(record.inventoryItem == nil)
        #expect(record.shoppingLocation == nil)
        #expect(try context.count(for: NSFetchRequest<PurchaseRecord>(entityName: "PurchaseRecord")) == 1)
    }

    @Test func deletingTheProductRemovesItsRecords() throws {
        let (product, _, _, _) = try makeRecord()
        context.delete(product)
        try context.save()
        #expect(try context.count(for: NSFetchRequest<PurchaseRecord>(entityName: "PurchaseRecord")) == 0)
    }
}
