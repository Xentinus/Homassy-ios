import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Price history")
struct PriceHistoryTests {
    let stack: ShoppingTestStack
    var inventory: InventoryService { stack.inventory }
    init() throws { stack = try ShoppingTestStack() }

    private func entry(_ price: Decimal, _ quantity: Decimal = 1, unit: MeasureUnit = .liter, currency: String = "HUF",
                       store: UUID? = nil, name: String? = nil, day: Int) -> PriceEntry {
        PriceEntry(id: UUID(), date: Date(timeIntervalSince1970: 1_790_000_000 + TimeInterval(day) * 86_400),
                   storeID: store, storeName: name, quantity: quantity, unit: unit, price: price, currency: currency)
    }

    @Test func unitPriceIsThePaidAmountPerUnit() {
        #expect(entry(900, 2, day: 0).unitPrice == 450)
        #expect(entry(900, 0, day: 0).unitPrice == 900)
    }

    @Test func averageUsesTheMostCommonCurrencyAndUnit() throws {
        let entries = [entry(900, 2, day: 0), entry(500, 1, day: 1), entry(3, 1, currency: "EUR", day: 2),
                       entry(2000, 1, unit: .kilogram, day: 3)]
        let average = try #require(PriceHistory.summary(of: entries).average)
        #expect(average.currency == "HUF")
        #expect(average.unit == .liter)
        #expect(average.unitPrice == 475)                               // (450 + 500) / 2
        #expect(average.count == 2)
        #expect(PriceHistory.summary(of: []).average == nil)
    }

    @Test func currencyTiesGoToThePreferredOne() throws {
        let entries = [entry(3, day: 0), entry(900, currency: "EUR", day: 1)]
        #expect(PriceHistory.summary(of: entries, preferredCurrency: "EUR").average?.currency == "EUR")
        #expect(PriceHistory.summary(of: entries, preferredCurrency: "HUF").average?.currency == "HUF")
    }

    @Test func eachStoreShowsItsLatestPurchaseNewestFirst() throws {
        let spar = UUID(), aldi = UUID()
        let entries = [entry(400, store: spar, name: "Spar", day: 0), entry(420, store: spar, name: "Spar", day: 5),
                       entry(390, store: aldi, name: "Aldi", day: 3), entry(450, day: 1)]
        let stores = PriceHistory.summary(of: entries).stores
        #expect(stores.map(\.name) == ["Spar", "Aldi", nil])
        #expect(stores[0].latest.price == 420)
        #expect(stores[0].count == 2)
        #expect(stores[2].key == PriceHistory.noStoreKey)
        #expect(PriceHistory.chart(entries, storeKey: spar.uuidString).map(\.price) == [400, 420])
    }

    @Test func entriesComeFromRecordsAndOlderPricedStock() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        // A record without inventory, stock with a price (which writes its own record), and legacy stock.
        try inventory.recordPurchase(product: milk, quantity: 2, unit: .liter, price: 900, currency: "HUF",
                                     store: spar, purchasedAt: stack.now.date)
        try inventory.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: nil, purchasedAt: nil,
                               price: 480, currency: "HUF", storageLocation: nil, shoppingLocation: nil)
        try inventory.recordPurchase(product: milk, quantity: 1, unit: .liter, price: nil, currency: nil,
                                     store: spar, purchasedAt: nil)                     // no price: not an entry
        let legacy = stack.spaceStore.insert(InventoryItem.self, in: stack.space, by: stack.user)
        legacy.product = milk
        legacy.quantity = 1
        legacy.unit = .liter
        legacy.price = 500
        legacy.currency = "HUF"
        try stack.context.save()

        let entries = PriceHistory.entries(for: milk, defaultCurrency: "HUF")
        #expect(entries.map(\.price).sorted() == [480, 500, 900])
        #expect(entries.first { $0.price == 900 }?.storeName == "Spar")
        #expect(entries.first { $0.price == 900 }?.unitPrice == 450)
    }
}
