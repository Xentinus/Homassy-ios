import CoreData
import Foundation
import HomassyShared
import Testing
@testable import HomassyCore

@MainActor
@Suite("ShoppingActivityCoordinator")
struct ShoppingActivityCoordinatorTests {
    let stack: ShoppingTestStack
    let controller = FakeLiveActivityController()
    let memory: ShoppingActivityMemory
    let coordinator: ShoppingActivityCoordinator
    let spar: ShoppingLocation
    let weekly: ShoppingList
    let party: ShoppingList
    let atSpar = Coordinate(latitude: 47.4600, longitude: 18.9500)
    let nearSpar = Coordinate(latitude: 47.4605, longitude: 18.9500)      // about 55 m
    let farAway = Coordinate(latitude: 47.4800, longitude: 18.9500)       // about 2.2 km

    init() throws {
        stack = try ShoppingTestStack()
        memory = ShoppingActivityMemory(defaults: UserDefaults(suiteName: "ShoppingActivityCoordinatorTests.\(UUID().uuidString)")!)
        let clock = stack.now
        coordinator = ShoppingActivityCoordinator(shopping: stack.service, inventory: stack.inventory,
                                                  pending: stack.pending, controller: controller, memory: memory,
                                                  locale: Locale(identifier: "hu_HU"), now: { clock.date },
                                                  debounce: .zero)
        spar = try stack.makeStore("Spar Budaörs")
        spar.latitude = 47.4600
        spar.longitude = 18.9500
        weekly = try stack.service.createList(name: "Heti", in: stack.space)
        party = try stack.service.createList(name: "Buli", in: stack.space)
        try stack.context.save()
    }

    @discardableResult
    func add(_ name: String, to list: ShoppingList? = nil, at store: ShoppingLocation? = nil) throws -> ShoppingListItem {
        try stack.service.addItem(to: list ?? weekly, customName: name, shoppingLocation: store ?? spar)
    }

    func arrive(_ position: Coordinate? = nil, branches: [ChainBranch] = []) async {
        await coordinator.evaluate(position: position ?? atSpar, branches: branches, preferredSpaceID: nil)
    }

    @Test func arrivingAtAStoreWithItemsStartsItsActivity() async throws {
        try add("Tej")
        try add("Chips", to: party)
        try add("Szappan", at: try stack.makeStore("Auchan"))
        await arrive()
        let request = try #require(controller.started.first)
        #expect(controller.started.count == 1)
        #expect(request.scope == .store(spar.publicId))
        #expect(request.spaceID == stack.space.publicId)
        #expect(request.content.title == "Spar Budaörs")
        #expect(request.content.listCount == 2)
        #expect(request.content.remainingCount == 2)
        #expect(request.staleDate == stack.now.date.addingTimeInterval(ShoppingActivityCoordinator.staleInterval))
        #expect(coordinator.current?.scope == .store(spar.publicId))
        #expect(memory.started?.activityID == "activity-1")
    }

    @Test func nothingStartsWithoutAPositionAwayFromStoresOrWhenTurnedOff() async throws {
        try add("Tej")
        await coordinator.evaluate(position: nil, branches: [], preferredSpaceID: nil)
        await arrive(farAway)
        controller.areActivitiesEnabled = false
        await arrive()
        #expect(controller.started.isEmpty)
        #expect(coordinator.current == nil)
    }

    @Test func aRefusedStartIsTriedAgainAtTheNextForeground() async throws {
        try add("Tej")
        controller.refusesStart = true
        await arrive()
        #expect(coordinator.current == nil)
        controller.refusesStart = false
        await arrive()
        #expect(controller.started.count == 1)
    }

    @Test func arrivingAgainAtTheSameStoreOnlyRefreshes() async throws {
        try add("Tej")
        await arrive()
        await arrive(nearSpar)
        #expect(controller.started.count == 1)
        #expect(controller.ended.isEmpty)
    }

    @Test func anotherStoreEndsTheFirstOneAtOnce() async throws {
        try add("Tej")
        let auchan = try stack.makeStore("Auchan Budaörs")
        auchan.latitude = 47.4700                                          // about 1.1 km north of the Spar
        auchan.longitude = 18.9500
        try add("Mosópor", at: auchan)
        await arrive()
        await arrive(Coordinate(latitude: 47.4700, longitude: 18.9500))
        #expect(controller.started.map(\.scope) == [.store(spar.publicId), .store(auchan.publicId)])
        #expect(controller.ended.first == .init(id: "activity-1", content: nil, dismissal: .immediate))
        #expect(controller.running().count == 1)
    }

    @Test func openingTheAppFarAwayEndsIt() async throws {
        try add("Tej")
        await arrive()
        await arrive(farAway)
        #expect(controller.ended.map(\.dismissal) == [.immediate])
        #expect(coordinator.current == nil)
        #expect(memory.started == nil)
    }

    @Test func changesUpdateTheActivityAndCountRowsThatLeft() async throws {
        let milk = try add("Tej")
        try add("Kenyér")
        await arrive()
        try stack.service.deleteItem(milk)
        try add("Vaj", to: party)
        await coordinator.refresh()
        let content = try #require(controller.latest)
        #expect(content.nextItems.map(\.name) == ["Kenyér", "Vaj"])
        #expect(content.remainingCount == 2)
        #expect(content.doneCount == 1)
        #expect(content.listCount == 2)
    }

    @Test func anUnchangedListSendsNoUpdate() async throws {
        try add("Tej")
        await arrive()
        await coordinator.refresh()
        await coordinator.refresh()
        #expect(controller.updates.isEmpty)
    }

    @Test func aTickBuysTheRowAndTheLastOneFinishesAfterFiveMinutes() async throws {
        try add("Tej")
        try add("Kenyér")
        await arrive()
        let first = try #require(controller.latest?.nextItems.first)
        await coordinator.tick(itemIDs: first.itemIDs)
        #expect(controller.latest?.remainingCount == 1)
        #expect(controller.latest?.doneCount == 1)

        let last = try #require(controller.latest?.nextItems.first)
        await coordinator.tick(itemIDs: last.itemIDs)
        let end = try #require(controller.ended.last)
        #expect(end.content?.isFinished == true)
        #expect(end.content?.doneCount == 2)
        #expect(end.dismissal == .after(stack.now.date.addingTimeInterval(ShoppingActivityCoordinator.finishedLinger)))
        #expect(coordinator.current == nil)
        #expect(memory.started == nil)
        #expect(memory.suppressed == nil)                   // finished is not a swipe
        #expect(try stack.count(ShoppingListItem.self) == 0)
    }

    @Test func deletingTheStoreEndsItAtOnce() async throws {
        try add("Tej")
        await arrive()
        stack.context.delete(spar)
        try stack.context.save()
        await coordinator.refresh()
        #expect(controller.ended.map(\.dismissal) == [.immediate])
    }

    @Test func aSwipedAwayActivityStaysAwayUntilTheUserLeft() async throws {
        try add("Tej")
        await arrive()
        controller.dismissByUser("activity-1")
        await arrive(nearSpar)
        #expect(controller.started.count == 1)                              // suppressed
        #expect(memory.suppressed?.scope == .store(spar.publicId))
        await arrive(farAway)                                               // left: suppression lifted
        #expect(memory.suppressed == nil)
        await arrive()
        #expect(controller.started.count == 2)
    }

    @Test func aSuppressionExpiresAfterFourHours() async throws {
        try add("Tej")
        await arrive()
        controller.dismissByUser("activity-1")
        await arrive()
        #expect(controller.started.count == 1)
        stack.now.advance(seconds: ShoppingActivityCoordinator.suppressionLifetime + 1)
        await arrive()
        #expect(controller.started.count == 2)
    }

    @Test func atAnUnsavedBranchTheChainsItemsShowUnderTheChainName() async throws {
        try add("Tej")
        let budakeszi = Coordinate(latitude: 47.5100, longitude: 18.9300)
        await arrive(budakeszi, branches: [ChainBranch(chainKey: "spar", center: budakeszi)])
        let request = try #require(controller.started.first)
        #expect(request.scope == .chain("spar"))
        #expect(request.content.title == "Spar")
        #expect(request.content.remainingCount == 1)
    }

    @Test func twoNearbyStoresMakeOneActivityWithBothStoresItems() async throws {
        let dm = try stack.makeStore("dm Budaörs")
        dm.latitude = 47.4602                                              // about 22 m from the Spar
        dm.longitude = 18.9500
        try add("Tej")
        try add("Fogkrém", to: party, at: dm)
        await arrive()
        let request = try #require(controller.started.first)
        #expect(request.scope == .stores([spar.publicId, dm.publicId].sorted { $0.uuidString < $1.uuidString }))
        #expect(request.content.title == "2 közeli bolt")
        #expect(request.content.remainingCount == 2)
    }

    @Test func anActivityFromAnEarlierProcessIsAdoptedAndExtraOnesEnd() async throws {
        let milk = try add("Tej")
        try add("Kenyér")
        let shown = ShoppingActivityContent(title: "Spar Budaörs", spaceName: stack.space.name, listCount: 1,
                                            remainingCount: 3, doneCount: 1, nextItems: [], canTick: true)
        controller.seed(RunningShoppingActivity(id: "old", spaceID: stack.space.publicId,
                                                scope: .store(spar.publicId), content: shown))
        controller.seed(RunningShoppingActivity(id: "extra", spaceID: stack.space.publicId,
                                                scope: .chain("auchan"), content: shown))
        try stack.service.deleteItem(milk)
        await coordinator.refresh()
        #expect(coordinator.current?.scope == .store(spar.publicId))
        #expect(controller.ended.map(\.id) == ["extra"])
        // 1 shown as done + 2 rows that left while no process ran (3 shown, 1 open at adoption).
        #expect(controller.latest?.doneCount == 3)
        #expect(controller.latest?.remainingCount == 1)
    }

    @Test func aTickInAFreshProcessAdoptsFirst() async throws {
        let milk = try add("Tej")
        try add("Kenyér")
        let shown = ShoppingActivityContent(title: "Spar Budaörs", spaceName: stack.space.name, listCount: 1,
                                            remainingCount: 2, doneCount: 0, nextItems: [], canTick: true)
        controller.seed(RunningShoppingActivity(id: "old", spaceID: stack.space.publicId,
                                                scope: .store(spar.publicId), content: shown))
        await coordinator.tick(itemIDs: [milk.publicId])
        #expect(controller.latest?.remainingCount == 1)
        #expect(controller.latest?.doneCount == 1)
    }

    @Test func aReadOnlyHouseholdShowsItemsWithoutTicks() async throws {
        try add("Tej")
        let readOnly = ShoppingActivityCoordinator(
            shopping: ShoppingService(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user,
                                      canEdit: { _ in false }),
            inventory: stack.inventory, pending: stack.pending, controller: controller, memory: memory,
            debounce: .zero)
        await readOnly.evaluate(position: atSpar, branches: [], preferredSpaceID: nil)
        #expect(controller.started.first?.content.canTick == false)
    }
}
