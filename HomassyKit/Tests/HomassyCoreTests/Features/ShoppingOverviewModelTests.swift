import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Shopping overview model")
struct ShoppingOverviewModelTests {
    let stack: ShoppingTestStack
    let queue = UndoQueue(window: .seconds(3600))
    let locale = Locale(identifier: "en_US")
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()
    let defaults: UserDefaults

    init() throws {
        stack = try ShoppingTestStack()
        defaults = try #require(UserDefaults(suiteName: "test.shoppingOverview.\(UUID().uuidString)"))
    }

    private func makeModel(distances: [UUID: Double] = [:]) -> ShoppingOverviewModel {
        let clock = stack.now
        return ShoppingOverviewModel(service: stack.service, space: stack.space, undoQueue: queue,
                                     pending: stack.pending, preferences: ShoppingHomePreferences(defaults: defaults),
                                     distance: { distances[$0] }, storeTitle: { _ in nil },
                                     locale: locale, calendar: calendar, now: { clock.date })
    }

    /// "list:Heti", "store:Aldi@300", "store:Spar", "noStore".
    private func label(_ section: ShoppingOverviewModel.Section) -> String {
        switch section.kind {
        case .list(let chip): "list:\(chip.name)"
        case .store(_, let title, let distance): "store:\(title)" + (distance.map { "@\(Int($0))" } ?? "")
        case .noStore: "noStore"
        }
    }

    private func names(_ section: ShoppingOverviewModel.Section) -> [String] { section.rows.map(\.name) }

    // MARK: Lists and chips

    @Test func listGroupingHasASectionPerListInListOrder() throws {
        let heti = try stack.service.createList(name: "Heti", color: "#e0533b", in: stack.space)
        let drog = try stack.service.createList(name: "Drogéria", in: stack.space)
        try stack.service.createList(name: "Üres", in: stack.space)
        try stack.service.addItem(to: heti, customName: "A")
        try stack.service.addItem(to: heti, customName: "B")
        try stack.service.addItem(to: drog, customName: "C")

        let model = makeModel()
        #expect(model.sections.map(label) == ["list:Heti", "list:Drogéria"])      // no section for an empty list
        #expect(model.sections.map(names) == [["A", "B"], ["C"]])
        #expect(model.chips.map(\.name) == ["Heti", "Drogéria", "Üres"])
        #expect(model.chips.map(\.remaining) == [2, 1, 0])
        #expect(model.chips.first?.color == "#e0533b")
        #expect(model.totalCount == 3)
        #expect(model.hasLists && model.showsStrip && model.showsListHeaders && model.canReorder)
    }

    @Test func oneListHidesTheStripAndTheHeaders() throws {
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        try stack.service.addItem(to: heti, customName: "A")
        let model = makeModel()
        #expect(!model.showsStrip)
        #expect(!model.showsListHeaders)
        #expect(model.sections.map(names) == [["A"]])
    }

    @Test func noListsAtAll() {
        let model = makeModel()
        #expect(!model.hasLists)
        #expect(model.sections.isEmpty)
        #expect(model.totalCount == 0)
    }

    @Test func rowsDescribeTheItemsStillToBuy() throws {
        let list = try stack.service.createList(name: "Heti", color: "#3a82f6", in: stack.space)
        let spar = try stack.makeStore("Spar")
        let deadline = stack.now.date.addingTimeInterval(86_400)
        try stack.service.addItem(to: list, customName: "Alma", quantity: 2, unit: .kilogram, note: "piros",
                                  deadline: deadline, shoppingLocation: spar)
        let legacy = try stack.service.addItem(to: list, customName: "Kenyér")
        try stack.service.togglePurchased(legacy)            // bought before the 2026-09-25 revision

        let model = makeModel()
        let apple = try #require(model.sections.first?.rows.first)
        #expect(model.totalCount == 1)
        #expect(apple.name == "Alma")
        #expect(apple.listID == list.publicId)
        #expect(apple.listName == "Heti")
        #expect(apple.listColor == "#3a82f6")
        #expect(apple.quantityText == Quantity.format(2, unit: .kilogram, locale: locale))
        #expect(apple.note == "piros")
        #expect(apple.storeName == "Spar")
        #expect(apple.storeID == spar.publicId)
        #expect(apple.deadline == deadline)
        #expect(apple.productID == nil)
    }

    @Test func productRowsCarryTheProductForTheCard() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        milk.image = Data([1, 2, 3])
        try stack.context.save()
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        try stack.service.addItem(to: list, product: milk)
        let row = try #require(makeModel().sections.first?.rows.first)
        #expect(row.productID == milk.publicId)
        #expect(row.image == Data([1, 2, 3]))
    }

    @Test func deadlinesAreStyledLikeExpiry() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let day: TimeInterval = 86_400
        try stack.service.addItem(to: list, customName: "Ráér", deadline: stack.now.date.addingTimeInterval(30 * day))
        try stack.service.addItem(to: list, customName: "Hamarosan", deadline: stack.now.date.addingTimeInterval(10 * day))
        try stack.service.addItem(to: list, customName: "Holnap", deadline: stack.now.date.addingTimeInterval(day))
        try stack.service.addItem(to: list, customName: "Lejárt", deadline: stack.now.date.addingTimeInterval(-2 * day))
        try stack.service.addItem(to: list, customName: "Nincs")

        let rows = makeModel().sections.flatMap(\.rows)
        let levels = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.deadlineLevel) })
        #expect(levels["Ráér"] == .ok)
        #expect(levels["Hamarosan"] == .soon)
        #expect(levels["Holnap"] == .critical)
        #expect(levels["Lejárt"] == .expired)
        #expect(levels["Nincs"] == ExpirationLevel.none)
    }

    // MARK: Filter

    @Test func theFilterShowsOneListWithoutHeadersAndIsRemembered() throws {
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        let drog = try stack.service.createList(name: "Drogéria", in: stack.space)
        try stack.service.addItem(to: heti, customName: "A")
        try stack.service.addItem(to: drog, customName: "C")

        let model = makeModel()
        model.filter = drog.publicId
        #expect(model.sections.map(names) == [["C"]])
        #expect(!model.showsListHeaders)
        #expect(model.showsStrip)
        #expect(model.totalCount == 2)                        // the "Mind" chip still counts everything
        #expect(makeModel().filter == drog.publicId)
    }

    @Test func aDeletedFilteredListFallsBackToAll() throws {
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        let drog = try stack.service.createList(name: "Drogéria", in: stack.space)
        try stack.service.addItem(to: heti, customName: "A")

        let model = makeModel()
        model.filter = drog.publicId
        try stack.service.deleteList(drog)
        model.reload()
        #expect(model.filter == nil)
        #expect(ShoppingHomePreferences(defaults: defaults).filter(for: stack.space.publicId) == nil)
        #expect(model.sections.map(names) == [["A"]])
    }

    // MARK: Store grouping

    @Test func storeGroupingOrdersNearestFirstThenItemsWithoutAStore() throws {
        let spar = try stack.makeStore("Spar")
        let aldi = try stack.makeStore("Aldi")
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        let drog = try stack.service.createList(name: "Drogéria", in: stack.space)
        try stack.service.addItem(to: heti, customName: "A", shoppingLocation: spar)
        try stack.service.addItem(to: heti, customName: "B")
        try stack.service.addItem(to: heti, customName: "C", shoppingLocation: aldi)
        try stack.service.addItem(to: drog, customName: "D", shoppingLocation: spar)

        let model = makeModel(distances: [aldi.publicId: 300, spar.publicId: 900])
        model.grouping = .store
        #expect(model.sections.map(label) == ["store:Aldi@300", "store:Spar@900", "noStore"])
        #expect(model.sections.map(names) == [["C"], ["A", "D"], ["B"]])   // list order, then item order
        #expect(!model.canReorder)
        #expect(!model.showsListHeaders)
        #expect(makeModel().grouping == .store)
    }

    @Test func storeGroupingWithoutALocationIsAlphabetical() throws {
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        for name in ["Spar", "Aldi", "Coop"] {
            try stack.service.addItem(to: heti, customName: "x-\(name)", shoppingLocation: try stack.makeStore(name))
        }
        let model = makeModel()
        model.grouping = .store
        #expect(model.sections.map(label) == ["store:Aldi", "store:Coop", "store:Spar"])
    }

    @Test func aKnownDistanceComesBeforeAnUnknownOne() throws {
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        let aldi = try stack.makeStore("Aldi")
        let zoo = try stack.makeStore("Zoo bolt")
        try stack.service.addItem(to: heti, customName: "A", shoppingLocation: aldi)
        try stack.service.addItem(to: heti, customName: "Z", shoppingLocation: zoo)
        let model = makeModel(distances: [zoo.publicId: 5_000])
        model.grouping = .store
        #expect(model.sections.map(label) == ["store:Zoo bolt@5000", "store:Aldi"])
    }

    @Test func theFilterAlsoAppliesToStoreGrouping() throws {
        let spar = try stack.makeStore("Spar")
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        let drog = try stack.service.createList(name: "Drogéria", in: stack.space)
        try stack.service.addItem(to: heti, customName: "A", shoppingLocation: spar)
        try stack.service.addItem(to: drog, customName: "D", shoppingLocation: spar)
        try stack.service.addItem(to: drog, customName: "E")

        let model = makeModel()
        model.grouping = .store
        model.filter = drog.publicId
        #expect(model.sections.map(label) == ["store:Spar", "noStore"])
        #expect(model.sections.map(names) == [["D"], ["E"]])
    }

    // MARK: Delete and reorder

    @Test func deleteHidesTheRowAndItsCountAndUndoBringsItBack() throws {
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        let bread = try stack.service.addItem(to: heti, customName: "Kenyér")
        try stack.service.addItem(to: heti, customName: "Tej")
        let model = makeModel()

        model.delete(bread.publicId)
        #expect(model.sections.map(names) == [["Tej"]])
        #expect(model.chips.map(\.remaining) == [1])
        queue.undo(try #require(queue.pending.first).id)
        #expect(model.sections.map(names) == [["Kenyér", "Tej"]])

        model.delete(bread.publicId)
        try queue.commitAll()
        model.reload()
        #expect(model.totalCount == 1)
        #expect(try stack.service.items(in: heti).map(ShoppingService.displayName(of:)) == ["Tej"])
    }

    @Test func dragOntoAnotherCardReordersWithinTheList() throws {
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        let a = try stack.service.addItem(to: heti, customName: "A")
        try stack.service.addItem(to: heti, customName: "B")
        let c = try stack.service.addItem(to: heti, customName: "C")
        let model = makeModel()

        model.moveItem(c.publicId, onto: a.publicId)
        #expect(model.sections.map(names) == [["C", "A", "B"]])
        #expect(makeModel().sections.map(names) == [["C", "A", "B"]])
        model.moveItem(c.publicId, onto: try #require(model.sections.first?.rows.last).id)
        #expect(model.sections.map(names) == [["A", "B", "C"]])
        model.moveItem(a.publicId, onto: a.publicId)
        #expect(model.sections.map(names) == [["A", "B", "C"]])
    }

    @Test func dragAcrossListsOrInStoreGroupingDoesNothing() throws {
        let heti = try stack.service.createList(name: "Heti", in: stack.space)
        let drog = try stack.service.createList(name: "Drogéria", in: stack.space)
        let a = try stack.service.addItem(to: heti, customName: "A")
        let b = try stack.service.addItem(to: heti, customName: "B")
        let d = try stack.service.addItem(to: drog, customName: "D")
        let model = makeModel()

        model.moveItem(d.publicId, onto: a.publicId)
        #expect(model.sections.map(names) == [["A", "B"], ["D"]])
        model.grouping = .store
        model.moveItem(b.publicId, onto: a.publicId)
        model.grouping = .list
        #expect(model.sections.map(names) == [["A", "B"], ["D"]])
    }
}
