import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("ServiceContainer and UITestSeed")
struct UITestSeedTests {
    func container(_ env: ServiceTestEnvironment) -> ServiceContainer {
        ServiceContainer(spaceStore: env.spaceStore, context: env.context, userRecordName: ServiceTestEnvironment.user)
    }

    @Test func activeSpaceFallsBackToPersonal() throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let services = container(env)
        #expect(services.activeSpace(selectedID: nil) == env.personal)
        #expect(services.activeSpace(selectedID: UUID()) == env.personal)
        #expect(services.activeSpace(selectedID: home.publicId) == home)
    }

    @Test func seedIsCompleteAndIdempotent() async throws {
        let env = try ServiceTestEnvironment()
        let services = container(env)
        try await UITestSeed.populate(services, in: env.personal)
        try await UITestSeed.populate(services, in: env.personal)
        #expect(try services.storageLocations.locations(in: env.personal).map(\.name) == ["Fridge", "Pantry", "Freezer"])
        #expect(try services.products.products(in: env.personal).map(\.name) == ["Apples", "Bread", "Eggs", "Milk"])
        #expect(try services.products.product(barcode: UITestSeed.knownBarcode, in: env.personal)?.name == "Milk")
        #expect(try services.shoppingLocations.recent(in: env.personal).map(\.name) == ["Corner Shop"])
        let corner = try #require(try services.shoppingLocations.recent(in: env.personal).first)
        #expect(services.storeDirectory.subtitle(ofStore: corner.publicId) == "Fő utca 1., Budapest")
    }

    @Test func upsertingAStoreWiresItsAddressIntoTheDirectory() throws {
        let env = try ServiceTestEnvironment()
        let services = container(env)
        let store = try services.shoppingLocations.upsert(
            StoreResult(mapItemIdentifier: "I-W", name: "W", latitude: 47.5, longitude: 19.0,
                        subtitle: "Fő utca 1., Budapest"),
            in: env.personal)
        #expect(services.storeDirectory.subtitle(ofStore: store.publicId) == "Fő utca 1., Budapest")
    }

    @Test func storeItemsSeedTwoListsAtCornerShop() async throws {
        let env = try ServiceTestEnvironment()
        let services = container(env)
        try await UITestSeed.populate(services, in: env.personal)
        try UITestSeed.populateStoreItems(services, in: env.personal)
        let lists = try services.shopping.lists(in: env.personal)
        #expect(lists.map(\.name) == ["Weekly", "Party"])
        let items = try lists.flatMap { try services.shopping.unpurchasedItems(in: $0) }
        #expect(items.map(ShoppingService.displayName(of:)) == ["Milk", "Soap", "Milk", "Napkins"])
        #expect(items.filter { $0.shoppingLocation?.name == "Corner Shop" }.count == 3)
    }
}
