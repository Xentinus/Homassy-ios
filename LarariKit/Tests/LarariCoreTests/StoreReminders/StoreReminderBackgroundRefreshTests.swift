import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Store reminders in a background refresh")
struct StoreReminderBackgroundRefreshTests {
    let env: ServiceTestEnvironment
    let home = Coordinate(latitude: 47.50, longitude: 19.05)
    let csomor = StoreResult(mapItemIdentifier: "c", name: "Auchan Csömör", latitude: 47.55, longitude: 19.23)

    init() throws {
        env = try ServiceTestEnvironment()
    }

    func addItem(_ name: String, store storeName: String) throws {
        let list = env.spaceStore.insert(ShoppingList.self, in: env.personal, by: ServiceTestEnvironment.user)
        list.space = env.personal
        list.name = "Weekly"
        let item = env.spaceStore.insert(ShoppingListItem.self, in: env.personal, by: ServiceTestEnvironment.user)
        item.shoppingList = list
        item.customName = name
        let store = env.spaceStore.insert(ShoppingLocation.self, in: env.personal, by: ServiceTestEnvironment.user)
        store.space = env.personal
        store.name = storeName
        store.latitude = 47.46
        store.longitude = 18.95
        item.shoppingLocation = store
        try env.context.save()
    }

    func coordinator(center: FakeNotificationCenter, search: FakeStoreSearch, location: FakeLocation,
                     enabled: Bool = true) -> StoreReminderCoordinator {
        StoreReminderCoordinator(context: env.context, center: center, search: search, location: location,
                                 isEnabled: { enabled }, locale: Locale(identifier: "en_US"), debounce: .zero)
    }

    @Test func usesTheLastKnownPositionAndNeverAsksForALiveOne() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        let search = FakeStoreSearch(search: ["Auchan": [csomor]])
        let location = FakeLocation(access: .authorized, coordinate: nil, lastKnown: home)

        await coordinator(center: center, search: search, location: location).refreshInBackground()

        #expect(location.liveRequests == 0)
        #expect(search.calls == [.search(text: "Auchan", latitude: 47.50, longitude: 19.05)])
        #expect(await center.identifiers == ["store-auchan-0", "store-auchan-1"])
    }

    @Test func withoutALastKnownPositionTheRemindersStayAsTheyAre() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        await center.seedLocation(["store-auchan-0", "store-auchan-1"])
        let search = FakeStoreSearch(search: ["Auchan": [csomor]])

        await coordinator(center: center, search: search,
                          location: FakeLocation(access: .authorized, coordinate: home, lastKnown: nil))
            .refreshInBackground()

        #expect(search.calls.isEmpty)
        #expect(await center.removed.isEmpty)
        #expect(await center.identifiers == ["store-auchan-0", "store-auchan-1"])
    }

    @Test func aFailedSearchLeavesTheRemindersAsTheyAre() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        await center.seedLocation(["store-auchan-0", "store-auchan-1"])
        let search = FakeStoreSearch(search: ["Auchan": [csomor]], fails: true)

        await coordinator(center: center, search: search,
                          location: FakeLocation(access: .authorized, coordinate: nil, lastKnown: home))
            .refreshInBackground()

        #expect(search.calls == [.search(text: "Auchan", latitude: 47.50, longitude: 19.05)])
        #expect(await center.removed.isEmpty)
        #expect(await center.identifiers == ["store-auchan-0", "store-auchan-1"])
    }

    @Test func aFailedSearchInTheForegroundStillReschedulesToTheAssignedStores() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        await center.seedLocation(["store-auchan-0", "store-auchan-1"])
        let search = FakeStoreSearch(fails: true)

        await coordinator(center: center, search: search,
                          location: FakeLocation(access: .authorized, coordinate: home, lastKnown: nil)).refresh()

        #expect(await center.identifiers == ["store-auchan-0"])
    }

    @Test func deniedAccessRemovesWithoutAskingForALivePosition() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        await center.seedLocation(["store-auchan-0", "store-auchan-1"])
        let location = FakeLocation(access: .denied, coordinate: home, lastKnown: home)

        await coordinator(center: center, search: FakeStoreSearch(), location: location).refreshInBackground()

        #expect(await center.identifiers.isEmpty)
        #expect(location.liveRequests == 0)
    }

    @Test func switchedOffStillRemoves() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let center = FakeNotificationCenter()
        await center.seedLocation(["store-auchan-0"])
        await coordinator(center: center, search: FakeStoreSearch(),
                          location: FakeLocation(access: .authorized, lastKnown: home), enabled: false)
            .refreshInBackground()
        #expect(await center.identifiers.isEmpty)
    }

    @Test func nothingWaitingStillRemoves() async throws {
        let center = FakeNotificationCenter()
        await center.seedLocation(["store-auchan-0"])
        await coordinator(center: center, search: FakeStoreSearch(),
                          location: FakeLocation(access: .authorized, lastKnown: home))
            .refreshInBackground()
        #expect(await center.identifiers.isEmpty)
    }

    @Test func foregroundRefreshStillUsesTheLivePosition() async throws {
        try addItem("Milk", store: "Auchan Budaörs")
        let location = FakeLocation(access: .authorized, coordinate: home, lastKnown: nil)
        await coordinator(center: FakeNotificationCenter(), search: FakeStoreSearch(), location: location).refresh()
        #expect(location.liveRequests == 1)
    }
}
