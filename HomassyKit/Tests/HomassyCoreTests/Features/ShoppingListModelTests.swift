import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Shopping list model")
struct ShoppingListModelTests {
    let stack: ShoppingTestStack
    let queue = UndoQueue(window: .seconds(3600))
    let locale = Locale(identifier: "en_US")
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()

    init() throws { stack = try ShoppingTestStack() }

    private func makeModel(_ list: ShoppingList) -> ShoppingListModel {
        let clock = stack.now
        return ShoppingListModel(service: stack.service, list: list, undoQueue: queue, pending: stack.pending,
                                 locale: locale, calendar: calendar, now: { clock.date })
    }

    @Test func rowsDescribeTheItemsStillToBuy() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let spar = try stack.makeStore("Spar")
        let deadline = stack.now.date.addingTimeInterval(86_400)
        try stack.service.addItem(to: list, customName: "Alma", quantity: 2, unit: .kilogram, note: "piros",
                                  deadline: deadline, shoppingLocation: spar)
        let legacy = try stack.service.addItem(to: list, customName: "Kenyér")
        try stack.service.togglePurchased(legacy)            // bought before the 2026-09-25 revision

        let model = makeModel(list)
        #expect(model.listName == "Heti")
        #expect(model.remaining.map(\.name) == ["Alma"])
        let apple = try #require(model.remaining.first)
        #expect(apple.quantityText == Quantity.format(2, unit: .kilogram, locale: locale))
        #expect(apple.note == "piros")
        #expect(apple.storeName == "Spar")
        #expect(apple.deadline == deadline)
        #expect(apple.productID == nil)
        #expect(model.totalCount == 1)
    }

    @Test func productRowsCarryTheProductForTheCard() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        milk.image = Data([1, 2, 3])
        try stack.context.save()
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        try stack.service.addItem(to: list, product: milk)
        let row = try #require(makeModel(list).remaining.first)
        #expect(row.productID == milk.publicId)
        #expect(row.image == Data([1, 2, 3]))
    }


    @Test func deleteHidesAndUndoBringsBack() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let bread = try stack.service.addItem(to: list, customName: "Kenyér")
        let model = makeModel(list)

        model.delete(bread.publicId)
        #expect(model.remaining.isEmpty)
        queue.undo(try #require(queue.pending.first).id)
        #expect(model.remaining.map(\.name) == ["Kenyér"])

        model.delete(bread.publicId)
        try queue.commitAll()
        model.reload()
        #expect(model.totalCount == 0)
        #expect(try stack.service.items(in: list).isEmpty)
    }

    @Test func moveRemainingPersists() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        for name in ["A", "B", "C"] { try stack.service.addItem(to: list, customName: name) }
        let model = makeModel(list)

        model.moveRemaining(fromOffsets: IndexSet([2]), toOffset: 0)
        #expect(model.remaining.map(\.name) == ["C", "A", "B"])
        #expect(makeModel(list).remaining.map(\.name) == ["C", "A", "B"])
    }

    @Test func dragOntoAnotherCardMovesIt() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let a = try stack.service.addItem(to: list, customName: "A")
        try stack.service.addItem(to: list, customName: "B")
        let c = try stack.service.addItem(to: list, customName: "C")
        let model = makeModel(list)

        model.moveItem(c.publicId, onto: a.publicId)
        #expect(model.remaining.map(\.name) == ["C", "A", "B"])
        model.moveItem(c.publicId, onto: try #require(model.remaining.last).id)
        #expect(model.remaining.map(\.name) == ["A", "B", "C"])
        model.moveItem(a.publicId, onto: a.publicId)
        #expect(model.remaining.map(\.name) == ["A", "B", "C"])
    }

    @Test func deadlinesAreStyledLikeExpiry() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let day: TimeInterval = 86_400
        try stack.service.addItem(to: list, customName: "Ráér", deadline: stack.now.date.addingTimeInterval(30 * day))
        try stack.service.addItem(to: list, customName: "Hamarosan", deadline: stack.now.date.addingTimeInterval(10 * day))
        try stack.service.addItem(to: list, customName: "Holnap", deadline: stack.now.date.addingTimeInterval(day))
        try stack.service.addItem(to: list, customName: "Lejárt", deadline: stack.now.date.addingTimeInterval(-2 * day))
        try stack.service.addItem(to: list, customName: "Nincs")

        let levels = Dictionary(uniqueKeysWithValues: makeModel(list).remaining.map { ($0.name, $0.deadlineLevel) })
        #expect(levels["Ráér"] == .ok)
        #expect(levels["Hamarosan"] == .soon)
        #expect(levels["Holnap"] == .critical)
        #expect(levels["Lejárt"] == .expired)
        #expect(levels["Nincs"] == ExpirationLevel.none)
    }
}
