import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Shopping lists model")
struct ShoppingListsModelTests {
    let stack: ShoppingTestStack
    init() throws { stack = try ShoppingTestStack() }

    private func makeModel() -> ShoppingListsModel {
        let model = ShoppingListsModel(service: stack.service, space: stack.space)
        model.reload()
        return model
    }

    @Test func summariesCountWhatIsLeftToBuy() throws {
        let weekly = try stack.service.createList(name: "Heti", color: "#E0A458", in: stack.space)
        try stack.service.addItem(to: weekly, customName: "Alma")
        let bread = try stack.service.addItem(to: weekly, customName: "Kenyér")
        try stack.service.togglePurchased(bread)
        let party = try stack.service.createList(name: "Buli", in: stack.space)

        let model = makeModel()
        #expect(model.summaries == [
            .init(id: weekly.publicId, name: "Heti", color: "#E0A458", remaining: 1),
            .init(id: party.publicId, name: "Buli", color: nil, remaining: 0)
        ])
        #expect(model.list(for: weekly.publicId) == weekly)
    }

    @Test func createValidatesAndReloads() {
        let model = makeModel()
        #expect(!model.createList(name: "   ", color: nil))
        #expect(model.errorMessage != nil)
        model.dismissError()
        #expect(model.errorMessage == nil)
        #expect(model.createList(name: "Heti", color: ShoppingListPalette.colors[0]))
        #expect(model.summaries.map(\.name) == ["Heti"])
        #expect(model.summaries.first?.color == ShoppingListPalette.colors[0])
    }

    @Test func updateDeleteAndMove() throws {
        let model = makeModel()
        model.createList(name: "A", color: nil)
        model.createList(name: "B", color: nil)
        model.createList(name: "C", color: nil)
        let a = try #require(model.summaries.first)

        #expect(model.updateList(a.id, name: "Alfa", color: "#4A90D9"))
        #expect(model.summaries.first?.name == "Alfa")
        #expect(!model.updateList(a.id, name: "", color: nil))

        model.move(fromOffsets: IndexSet([0]), toOffset: 3)
        #expect(model.summaries.map(\.name) == ["B", "C", "Alfa"])

        model.delete(a.id)
        #expect(model.summaries.map(\.name) == ["B", "C"])
        #expect(try stack.service.lists(in: stack.space).count == 2)
    }
}
