import Foundation
import Testing
@testable import HomassyCore

@Suite("StoreReminderPlanner")
struct StoreReminderPlannerTests {
    let en = Locale(identifier: "en_US")
    let home = Coordinate(latitude: 47.50, longitude: 19.05)
    let budaors = Coordinate(latitude: 47.46, longitude: 18.95)

    func item(_ name: String, store: String = "Auchan Budaörs", space: String = "Personal",
              at coordinate: Coordinate? = Coordinate(latitude: 47.46, longitude: 18.95)) -> WaitingItem {
        WaitingItem(name: name, spaceName: space, storeName: store, storeCoordinate: coordinate, storeLastUsedAt: nil)
    }

    func branch(_ id: String, _ name: String, _ latitude: Double, _ longitude: Double) -> StoreResult {
        StoreResult(mapItemIdentifier: id, name: name, latitude: latitude, longitude: longitude)
    }

    @Test func groupsByChainAcrossStoresAndSpaces() {
        let groups = StoreReminderPlanner.groups([
            item("Milk"), item("Bread", store: "AUCHAN Csömör", space: "Home"), item("Soap", store: "dm Allee"),
        ])
        #expect(groups.map(\.key) == ["auchan", "dm"])
        #expect(groups[0].items.map(\.name) == ["Milk", "Bread"])
        #expect(groups[0].displayName == "Auchan")
    }

    @Test func plansOneReminderPerBranchWithTheAssignedStoreAlwaysIncluded() {
        let groups = StoreReminderPlanner.groups([item("Milk"), item("Bread")])
        let plan = StoreReminderPlanner.plan(
            groups: groups,
            branches: ["auchan": [branch("a2", "Auchan Csömör", 47.55, 19.23), branch("x", "Aldi Budaörs", 47.51, 19.06)]],
            position: home, budget: 20, locale: en)

        #expect(plan.count == 2)                                   // Budaörs (assigned) + Csömör; the Aldi result is filtered out
        #expect(plan.allSatisfy { $0.identifier.hasPrefix("store-auchan-") })
        #expect(plan.allSatisfy { $0.radius == 150 })
        #expect(plan.contains { $0.center == budaors })
        #expect(plan[0].title == "Auchan nearby")
        #expect(plan[0].body == "2 items waiting: Bread, Milk")
    }

    @Test func nearestBranchesComeFirstAndFarOnesAreDropped() {
        let groups = StoreReminderPlanner.groups([item("Milk", at: nil)])
        let plan = StoreReminderPlanner.plan(
            groups: groups,
            branches: ["auchan": [branch("far", "Auchan Debrecen", 47.53, 21.63), branch("b", "Auchan Budaörs", 47.46, 18.95),
                                  branch("c", "Auchan Csömör", 47.55, 19.23)]],
            position: home, budget: 20, locale: en)
        #expect(plan.map(\.center) == [budaors, Coordinate(latitude: 47.55, longitude: 19.23)])   // Debrecen > 15 km
    }

    @Test func budgetIsSharedRoundRobinAcrossChains() {
        let groups = StoreReminderPlanner.groups([item("Milk"), item("Soap", store: "dm Allee", at: Coordinate(latitude: 47.47, longitude: 19.04))])
        let auchans = (0..<5).map { branch("a\($0)", "Auchan \($0)", 47.50 + Double($0) * 0.01, 19.05) }
        let plan = StoreReminderPlanner.plan(groups: groups, branches: ["auchan": auchans], position: home, budget: 3, locale: en)
        #expect(plan.count == 3)
        #expect(plan.filter { $0.identifier.hasPrefix("store-dm-") }.count == 1)
    }

    @Test func withoutPositionOnlyAssignedStoresAreUsed() {
        let groups = StoreReminderPlanner.groups([item("Milk")])
        let plan = StoreReminderPlanner.plan(groups: groups, branches: ["auchan": [branch("c", "Auchan Csömör", 47.55, 19.23)]],
                                             position: nil, budget: 20, locale: en)
        #expect(plan.map(\.center) == [budaors])
    }

    @Test func nearDuplicateCoordinatesCollapse() {
        let groups = StoreReminderPlanner.groups([item("Milk")])
        let plan = StoreReminderPlanner.plan(groups: groups, branches: ["auchan": [branch("b", "Auchan Budaörs", 47.4601, 18.9501)]],
                                             position: home, budget: 20, locale: en)
        #expect(plan.count == 1)
    }

    @Test func bodyListsThreeNamesThenMoreAndSpacesOnlyWhenMixed() {
        let single = StoreReminderPlanner.groups(["A", "B", "C", "D", "E"].map { item($0) })
        let body = StoreReminderPlanner.plan(groups: single, branches: [:], position: nil, budget: 1, locale: en)[0].body
        #expect(body == "5 items waiting: A, B, C and 2 more")

        let mixed = StoreReminderPlanner.groups([item("Milk"), item("Bread", space: "Home")])
        let mixedBody = StoreReminderPlanner.plan(groups: mixed, branches: [:], position: nil, budget: 1, locale: en)[0].body
        #expect(mixedBody == "2 items waiting: Bread (Home), Milk (Personal)")
    }

    @Test func hungarianText() {
        let groups = StoreReminderPlanner.groups([item("Tej")])
        let reminder = StoreReminderPlanner.plan(groups: groups, branches: [:], position: nil, budget: 1,
                                                 locale: Locale(identifier: "hu_HU"))[0]
        #expect(reminder.title == "Auchan a közelben")
        #expect(reminder.body == "1 tétel vár: Tej")
    }

    @Test func noItemsOrNoCoordinatesGiveNothing() {
        #expect(StoreReminderPlanner.plan(groups: [], branches: [:], position: home, budget: 20, locale: en).isEmpty)
        let noCoordinate = StoreReminderPlanner.groups([item("Milk", at: nil)])
        #expect(StoreReminderPlanner.plan(groups: noCoordinate, branches: [:], position: nil, budget: 20, locale: en).isEmpty)
    }
}
