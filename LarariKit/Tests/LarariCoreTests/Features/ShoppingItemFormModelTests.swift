import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Shopping item form model")
struct ShoppingItemFormModelTests {
    let stack: ShoppingTestStack
    let locale = Locale(identifier: "en_US")
    init() throws { stack = try ShoppingTestStack() }

    @Test func loadsTheItem() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let deadline = stack.now.date.addingTimeInterval(86_400)
        let item = try stack.service.addItem(to: list, product: milk, quantity: Decimal(string: "1.5") ?? 0,
                                             note: "zsíros", deadline: deadline, shoppingLocation: spar)

        let model = ShoppingItemFormModel(service: stack.service, item: item, locale: locale, now: stack.now.date)
        #expect(model.hasProduct)
        #expect(model.name == "Tej")
        #expect(model.quantityText == "1.5")
        #expect(model.unit == .liter)
        #expect(model.note == "zsíros")
        #expect(model.hasDeadline)
        #expect(model.deadline == deadline)
        #expect(model.store == .init(id: spar.publicId, name: "Spar"))
        #expect(model.space == stack.space)
        #expect(model.unitLabel(.kilogram) == "kilograms")                  // the name only, for 1.5
        #expect(model.units == MeasureUnit.allCases)
    }

    @Test func savesChanges() throws {
        let spar = try stack.makeStore("Spar")
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Kenyér")
        let model = ShoppingItemFormModel(service: stack.service, item: item, locale: locale, now: stack.now.date)
        #expect(!model.hasDeadline)

        model.name = "Rozskenyér"
        model.quantityText = "2"
        model.unit = .piece
        model.note = "szeletelt"
        model.hasDeadline = true
        let deadline = stack.now.date.addingTimeInterval(172_800)
        model.deadline = deadline
        model.setStore(spar)

        #expect(model.save())
        #expect(item.customName == "Rozskenyér")
        #expect(item.quantity == 2)
        #expect(item.note == "szeletelt")
        #expect(item.deadline == deadline)
        #expect(item.shoppingLocation == spar)
        #expect(!stack.context.hasChanges)
    }

    @Test func clearingDeadlineAndStore() throws {
        let spar = try stack.makeStore("Spar")
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Kenyér", deadline: stack.now.date,
                                             shoppingLocation: spar)
        let model = ShoppingItemFormModel(service: stack.service, item: item, locale: locale, now: stack.now.date)
        model.hasDeadline = false
        model.setStore(nil)
        #expect(model.store == nil)
        #expect(model.save())
        #expect(item.deadline == nil)
        #expect(item.shoppingLocation == nil)
    }

    @Test(arguments: ["abc", "0", "-1", ""])
    func invalidQuantityIsRejected(_ text: String) throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Kenyér")
        let model = ShoppingItemFormModel(service: stack.service, item: item, locale: locale, now: stack.now.date)
        model.quantityText = text
        #expect(!model.save())
        #expect(model.errorMessage == ServiceError.quantityMustBePositive.errorDescription)
        #expect(item.quantity == 1)
    }

    @Test func blankCustomNameIsRejected() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Kenyér")
        let model = ShoppingItemFormModel(service: stack.service, item: item, locale: locale, now: stack.now.date)
        model.name = "  "
        #expect(!model.save())
        #expect(model.errorMessage == ServiceError.nameRequired.errorDescription)
        #expect(item.customName == "Kenyér")
    }
}
