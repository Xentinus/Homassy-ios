import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Add item flow model")
struct AddItemFlowModelTests {
    let stack: ShoppingTestStack
    let locations: ShoppingLocationService
    let locale = Locale(identifier: "en_US")

    init() throws {
        stack = try ShoppingTestStack()
        locations = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user)
    }

    private func makeModel(_ list: ShoppingList) -> AddItemFlowModel {
        AddItemFlowModel(list: list, shopping: stack.service, locations: locations, locale: locale)
    }

    @Test func productThenAmountThenStore() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let model = makeModel(list)
        #expect(model.step == .what)
        #expect(!model.canAdvance)

        model.query = "te"
        let suggestion = try #require(model.suggestions.first)
        model.chooseProduct(suggestion.id)
        #expect(model.step == .amount)
        #expect(model.chosenName == "Tej")
        #expect(model.unit == .liter)
        #expect(model.stepNumber == 2)
        #expect(model.unitLabel(.liter) == "liter")                   // no amount in the unit picker

        model.quantityText = "2"
        model.next()
        #expect(model.step == .store)
        model.setStore(spar)
        #expect(model.add())

        let item = try #require(try stack.service.items(in: list).first)
        #expect(item.product == milk)
        #expect(item.quantity == 2)
        #expect(item.unit == .liter)
        #expect(item.shoppingLocation == spar)
    }

    @Test func customNameUsesTheQueryAndPieces() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let model = makeModel(list)
        model.query = "  Szalvéta "
        #expect(model.canAdvance)
        model.next()
        #expect(model.step == .amount)
        #expect(model.chosenName == "Szalvéta")
        #expect(model.unit == .piece)
        model.next()
        #expect(model.add())
        let item = try #require(try stack.service.items(in: list).first)
        #expect(item.customName == "Szalvéta")
        #expect(item.product == nil)
        #expect(item.shoppingLocation == nil)
    }

    @Test func typingAProductNameExactlyPicksTheProduct() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let model = makeModel(list)
        model.query = "tej"
        model.next()
        model.next()
        #expect(model.add())
        #expect(try stack.service.items(in: list).first?.product == milk)
    }

    @Test func barcodeChoosesAKnownProduct() throws {
        try stack.makeProduct("Tej", unit: .liter, barcode: "5998200110039")
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let model = makeModel(list)
        #expect(!model.chooseBarcode("111"))
        #expect(model.step == .what)
        #expect(model.chooseBarcode("5998200110039"))
        #expect(model.chosenName == "Tej")
        #expect(model.step == .amount)
    }

    @Test func invalidAmountStaysAndBackGoesBack() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let model = makeModel(list)
        model.query = "Alma"
        model.next()
        model.quantityText = "0"
        #expect(!model.canAdvance)
        model.next()
        #expect(model.step == .amount)
        #expect(model.errorMessage != nil)
        model.quantityText = "3"
        model.next()
        model.back()
        #expect(model.step == .amount)
        model.back()
        #expect(model.step == .what)
        #expect(model.chosenName == nil)
    }

    @Test func suggestedPlaceIsStoredOnAdd() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let model = makeModel(list)
        model.query = "Alma"
        model.next()
        model.next()
        model.applySuggestion(.place(StoreSamples.sparAstoria, distance: 12))
        #expect(model.storeName == "Spar Astoria")
        #expect(model.suggestedDistance == 12)
        #expect(model.add())
        #expect(try stack.service.items(in: list).first?.shoppingLocation?.name == "Spar Astoria")
    }
}
