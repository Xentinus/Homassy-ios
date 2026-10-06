import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Proportional split")
struct ProportionalSplitTests {
    static func d(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    @Test func thirdsAddUpToTheTotal() {
        #expect(ProportionalSplit.split(total: 1000, weights: [1, 1, 1]) == [Self.d("333.33"), Self.d("333.33"), Self.d("333.34")])
    }

    @Test func evenAndUnevenWeights() {
        #expect(ProportionalSplit.split(total: 900, weights: [1, 1]) == [450, 450])
        #expect(ProportionalSplit.split(total: 1000, weights: [4, 2]) == [Self.d("666.67"), Self.d("333.33")])
        #expect(ProportionalSplit.split(total: Self.d("459.9"), weights: [Self.d("1.5"), Self.d("0.5")])
                == [Self.d("344.93"), Self.d("114.97")])
    }

    @Test func edgeCases() {
        #expect(ProportionalSplit.split(total: 0, weights: [1, 2]) == [0, 0])
        #expect(ProportionalSplit.split(total: 500, weights: [3]) == [500])
        #expect(ProportionalSplit.split(total: 500, weights: []).isEmpty)
    }

    @Test func textJoinsCurrencyAmounts() {
        let text = ProportionalSplit.text(total: 900, weights: [1, 1], currency: "EUR", locale: Locale(identifier: "en_US"))
        #expect(text == "€450.00 + €450.00")
    }
}

@MainActor
@Suite("InventoryService lots")
struct InventoryLotsTests {
    func corner(_ env: ServiceTestEnvironment) throws -> ShoppingLocation {
        try ShoppingLocationService(spaceStore: env.spaceStore, context: env.context,
                                    userRecordName: ServiceTestEnvironment.user)
            .upsert(StoreResult(mapItemIdentifier: "I-CORNER", name: "Corner", latitude: 47.5, longitude: 19.05),
                    in: env.personal)
    }

    @Test func lotsBecomeItemsWithTheirOwnLocationExpiryAndShare() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let fridge = try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let garage = try env.storageService().create(in: env.personal, name: "Garage", color: nil, isFreezer: false)
        let store = try corner(env)
        let items = try env.inventoryService().addStock(
            product: milk,
            lots: [LotDetails(quantity: 1, storageLocationID: fridge.publicId, expiresAt: env.day(7)),
                   LotDetails(quantity: 1, storageLocationID: garage.publicId, expiresAt: env.day(14))],
            unit: .piece, purchasedAt: env.day(0), totalPrice: 900, currency: nil, shoppingLocation: store)
        #expect(items.count == 2)
        #expect(items.map(\.storageLocation) == [fridge, garage])
        #expect(items.map(\.expiresAt) == [env.day(7), env.day(14)])
        #expect(items.map(\.price) == [450, 450])
        #expect(items.allSatisfy { $0.currency == "HUF" && $0.purchasedAt == env.day(0) && $0.shoppingLocation == store })
        #expect(try env.count(PurchaseRecord.self) == 2)
        #expect(!env.context.hasChanges)
    }

    @Test func withoutAPriceTheLotsHaveNone() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let items = try env.inventoryService().addStock(
            product: milk, lots: [LotDetails(quantity: 2), LotDetails(quantity: 3)], unit: .piece,
            purchasedAt: nil, totalPrice: nil, currency: nil, shoppingLocation: nil)
        #expect(items.map(\.price) == [nil, nil])
        #expect(items.map(\.quantity) == [2, 3])
    }

    @Test func oneBadLotAddsNothing() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let service = env.inventoryService()
        #expect(throws: ServiceError.expiryBeforePurchase) {
            _ = try service.addStock(product: milk, lots: [LotDetails(quantity: 1), LotDetails(quantity: 1, expiresAt: env.day(-2))],
                                     unit: .piece, purchasedAt: env.day(0), totalPrice: nil, currency: nil,
                                     shoppingLocation: nil)
        }
        #expect(throws: ServiceError.quantityMustBePositive) {
            _ = try service.addStock(product: milk, lots: [LotDetails(quantity: 1), LotDetails(quantity: 0)],
                                     unit: .piece, purchasedAt: nil, totalPrice: nil, currency: nil, shoppingLocation: nil)
        }
        #expect(throws: ServiceError.quantityMustBePositive) {
            _ = try service.addStock(product: milk, lots: [], unit: .piece, purchasedAt: nil, totalPrice: nil,
                                     currency: nil, shoppingLocation: nil)
        }
        #expect(try env.count(InventoryItem.self) == 0)
        #expect(try env.count(InventoryEvent.self) == 0)
    }

    @Test func aLocationOfAnotherSpaceIsRejected() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let milk = try await env.makeProduct("Milk")
        let shed = try env.storageService().create(in: home, name: "Shed", color: nil, isFreezer: false)
        #expect(throws: ServiceError.notFound) {
            _ = try env.inventoryService().addStock(
                product: milk, lots: [LotDetails(quantity: 1), LotDetails(quantity: 1, storageLocationID: shed.publicId)],
                unit: .piece, purchasedAt: nil, totalPrice: nil, currency: nil, shoppingLocation: nil)
        }
        #expect(try env.count(InventoryItem.self) == 0)
    }

    @Test func editCanChangeTheStore() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let item = try env.stock(milk, 1)
        let store = try corner(env)
        try env.inventoryService().update(item, quantity: 1, unit: .piece, expiresAt: nil, purchasedAt: nil, price: nil,
                                          currency: nil, storageLocation: nil, shoppingLocation: store)
        #expect(item.shoppingLocation == store)
        #expect(item.purchaseRecordSet.first?.shoppingLocation == store)
    }

    @Test func theOldEditKeepsTheStore() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let store = try corner(env)
        let item = try env.inventoryService().addStock(product: milk, quantity: 1, unit: .piece, expiresAt: nil,
                                                       purchasedAt: nil, price: nil, currency: nil, storageLocation: nil,
                                                       shoppingLocation: store)
        try env.inventoryService().update(item, quantity: 2, unit: .piece, expiresAt: nil, purchasedAt: nil, price: nil,
                                          currency: nil, storageLocation: nil)
        #expect(item.shoppingLocation == store && item.quantity == 2)
    }
}
