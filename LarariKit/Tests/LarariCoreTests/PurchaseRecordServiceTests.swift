import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Purchase records in the inventory service")
struct PurchaseRecordServiceTests {
    let stack: ShoppingTestStack
    var inventory: InventoryService { stack.inventory }
    init() throws { stack = try ShoppingTestStack() }

    private func records() throws -> [PurchaseRecord] {
        try stack.context.fetch(NSFetchRequest<PurchaseRecord>(entityName: "PurchaseRecord"))
    }

    @Test func recordsOnlyWithAPriceOrAStore() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        let priced = try #require(try inventory.recordPurchase(product: milk, quantity: 2, unit: .liter, price: 900,
                                                               currency: nil, store: nil, purchasedAt: nil))
        #expect(priced.currency == "HUF")                           // the service default
        #expect(priced.purchasedAt == stack.now.date)
        let stored = try #require(try inventory.recordPurchase(product: milk, quantity: 1, unit: .liter, price: nil,
                                                               currency: "EUR", store: spar, purchasedAt: nil))
        #expect(stored.currency == nil)                             // no price, no currency
        #expect(stored.shoppingLocation == spar)
        #expect(try inventory.recordPurchase(product: milk, quantity: 1, unit: .liter, price: nil, currency: nil,
                                             store: nil, purchasedAt: nil) == nil)
        #expect(try records().count == 2)
        #expect(!stack.context.hasChanges)
    }

    @Test func recordValidates() throws {
        let milk = try stack.makeProduct("Tej")
        let foreign = try stack.makeStore("Idegen", in: try stack.makeOtherSpace())
        #expect(throws: ServiceError.quantityMustBePositive) {
            _ = try inventory.recordPurchase(product: milk, quantity: 0, unit: .piece, price: 1, currency: nil,
                                             store: nil, purchasedAt: nil)
        }
        #expect(throws: ServiceError.notFound) {
            _ = try inventory.recordPurchase(product: milk, quantity: 1, unit: .piece, price: 1, currency: nil,
                                             store: foreign, purchasedAt: nil)
        }
    }

    @Test func addStockWithAPriceLinksItsRecord() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        let bought = Date(timeIntervalSince1970: 1_789_000_000)
        let item = try inventory.addStock(product: milk, quantity: 2, unit: .liter, expiresAt: nil, purchasedAt: bought,
                                          price: 899, currency: "HUF", storageLocation: nil, shoppingLocation: spar)
        let record = try #require(item.purchaseRecordSet.first)
        #expect(record.product == milk)
        #expect(record.quantity == 2)
        #expect(record.unit == .liter)
        #expect(record.price == 899)
        #expect(record.shoppingLocation == spar)
        #expect(record.purchasedAt == bought)

        _ = try inventory.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: nil, purchasedAt: nil,
                                   price: nil, currency: nil, storageLocation: nil, shoppingLocation: nil)
        #expect(try records().count == 1)                           // no price, no store: nothing to record
    }

    @Test func editingStockKeepsItsRecordInStep() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let item = try inventory.addStock(product: milk, quantity: 2, unit: .liter, expiresAt: nil, purchasedAt: nil,
                                          price: nil, currency: nil, storageLocation: nil, shoppingLocation: nil)
        #expect(item.purchaseRecordSet.isEmpty)

        try inventory.update(item, quantity: 2, unit: .liter, expiresAt: nil, purchasedAt: nil, price: 700,
                             currency: "HUF", storageLocation: nil)
        let record = try #require(item.purchaseRecordSet.first)
        #expect(record.price == 700)

        try inventory.update(item, quantity: 3, unit: .liter, expiresAt: nil, purchasedAt: nil, price: 750,
                             currency: "HUF", storageLocation: nil)
        #expect(record.price == 750)
        #expect(record.quantity == 3)
        #expect(try records().count == 1)

        try inventory.update(item, quantity: 3, unit: .liter, expiresAt: nil, purchasedAt: nil, price: nil,
                             currency: nil, storageLocation: nil)
        #expect(try records().isEmpty)
    }

    @Test func deletingTheStockItemKeepsThePrice() throws {
        let milk = try stack.makeProduct("Tej")
        let item = try inventory.addStock(product: milk, quantity: 1, unit: .piece, expiresAt: nil, purchasedAt: nil,
                                          price: 300, currency: nil, storageLocation: nil, shoppingLocation: nil)
        try inventory.delete(item)
        let record = try #require(try records().first)
        #expect(record.inventoryItem == nil)
        #expect(record.price == 300)
        #expect(record.product == milk)
    }
}
