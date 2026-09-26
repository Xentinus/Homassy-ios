import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("StoreReminderCoordinator")
struct StoreReminderCoordinatorTests {
    let persistence: PersistenceController
    let spaceStore: SpaceStore
    let personal: Space
    let home = Coordinate(latitude: 47.50, longitude: 19.05)
    var context: NSManagedObjectContext { persistence.viewContext }

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        spaceStore = SpaceStore(persistence: persistence, sharing: ShoppingNoShares())
        personal = try spaceStore.bootstrapPersonalSpace(userRecordName: "_me")
    }

    @discardableResult
    func addItem(_ name: String, store storeName: String?, purchased: Bool = false,
                 at coordinate: Coordinate = Coordinate(latitude: 47.46, longitude: 18.95)) throws -> ShoppingListItem {
        let list = spaceStore.insert(ShoppingList.self, in: personal, by: "_me")
        list.space = personal
        list.name = "Weekly"
        let item = spaceStore.insert(ShoppingListItem.self, in: personal, by: "_me")
        item.shoppingList = list
        item.customName = name
        item.isPurchased = purchased
        if let storeName {
            let store = spaceStore.insert(ShoppingLocation.self, in: personal, by: "_me")
            store.space = personal
            store.name = storeName
            store.latitude = coordinate.latitude
            store.longitude = coordinate.longitude
            item.shoppingLocation = store
        }
        try context.save()
        return item
    }

    func coordinator(center: FakeNotificationCenter, search: FakeStoreSearch = FakeStoreSearch(),
                     location: FakeLocation? = FakeLocation(access: .authorized, coordinate: Coordinate(latitude: 47.50, longitude: 19.05)),
                     enabled: Bool = true) -> StoreReminderCoordinator {
        StoreReminderCoordinator(context: context, center: center, search: search, location: location,
                                 isEnabled: { enabled }, locale: Locale(identifier: "en_US"), debounce: .zero)
    }

    @Test func waitingItemsAreOpenAndAssignedToAStore() throws {
        try addItem("Milk", store: "Auchan Budaörs")
        try addItem("Bread", store: nil)
        try addItem("Eggs", store: "Auchan Budaörs", purchased: true)
        let items = try StoreReminderCoordinator.waitingItems(in: context)
        #expect(items.map(\.name) == ["Milk"])
        #expect(items.first?.spaceName == personal.name)
    }

    @Test func schedulesAssignedStoreAndNearbyBranches() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        let search = FakeStoreSearch(search: ["Auchan": [StoreResult(mapItemIdentifier: "c", name: "Auchan Csömör",
                                                                     latitude: 47.55, longitude: 19.23)]])
        let coordinator = coordinator(center: center, search: search)

        await coordinator.refresh()

        #expect(coordinator.lastPlan.count == 2)
        #expect(search.calls == [.search(text: "Auchan", latitude: 47.50, longitude: 19.05)])
        #expect(await center.identifiers == ["store-auchan-0", "store-auchan-1"])
    }

    @Test func switchedOffOnlyRemoves() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        await center.seedLocation(["store-auchan-0"])
        let coordinator = coordinator(center: center, enabled: false)
        await coordinator.refresh()
        #expect(coordinator.lastPlan.isEmpty)
        #expect(await center.identifiers.isEmpty)
    }

    @Test func withoutLocationPermissionOnlyRemoves() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        await center.seedLocation(["store-auchan-0"])
        await coordinator(center: center, location: FakeLocation(access: .denied)).refresh()
        await coordinator(center: center, location: nil).refresh()
        #expect(await center.identifiers.isEmpty)
    }

    @Test func withoutPositionUsesAssignedStoresAndDoesNotSearch() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        let search = FakeStoreSearch()
        await coordinator(center: center, search: search, location: FakeLocation(access: .authorized, coordinate: nil)).refresh()
        #expect(search.calls.isEmpty)
        #expect(await center.identifiers == ["store-auchan-0"])
    }

    @Test func searchFailureKeepsAssignedStores() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        await coordinator(center: center, search: FakeStoreSearch(fails: true)).refresh()
        #expect(await center.identifiers == ["store-auchan-0"])
    }

    @Test func purchasingTheLastItemRemovesTheReminder() async throws {
        let item = try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        let coordinator = coordinator(center: center)
        await coordinator.refresh()
        item.isPurchased = true
        try context.save()
        await coordinator.refresh()
        #expect(await center.identifiers.isEmpty)
    }
}
