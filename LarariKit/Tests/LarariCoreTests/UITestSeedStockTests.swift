import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("UITestSeed stock")
struct UITestSeedStockTests {
    @Test func seedStocksFourItemsAndPricesMilk() async throws {
        let env = try ServiceTestEnvironment()
        let services = ServiceContainer(spaceStore: env.spaceStore, context: env.context, userRecordName: ServiceTestEnvironment.user)
        try await UITestSeed.populate(services, in: env.personal)
        let items = try services.inventory.items(in: env.personal)
        #expect(items.count == 4)
        #expect(Set(items.compactMap { $0.product?.name }) == ["Milk", "Bread", "Eggs", "Apples"])
        let milk = try #require(items.first { $0.product?.name == "Milk" })
        #expect(milk.price != nil && milk.storageLocation?.name == "Fridge")
    }
}
