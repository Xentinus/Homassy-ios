import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Shopping service")
struct ShoppingServiceTests {
    let stack: ShoppingTestStack
    var service: ShoppingService { stack.service }
    init() throws { stack = try ShoppingTestStack() }

    // MARK: Lists

    @Test func createListTrimsNameAndAppendsAtTheEnd() throws {
        let first = try service.createList(name: "  Heti  ", color: "#E0A458", in: stack.space)
        let second = try service.createList(name: "Buli", in: stack.space)
        #expect(first.name == "Heti")
        #expect(first.color == "#E0A458")
        #expect(first.space == stack.space)
        #expect(try service.lists(in: stack.space) == [first, second])
        #expect(!stack.context.hasChanges)
    }

    @Test func createListRequiresAName() {
        #expect(throws: ServiceError.nameRequired) { _ = try service.createList(name: "   ", in: stack.space) }
    }

    @Test func createListRejectsAReadOnlySpace() throws {
        let readOnly = ShoppingService(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user,
                                       canEdit: { _ in false })
        #expect(throws: ServiceError.readOnlySpace) { _ = try readOnly.createList(name: "Heti", in: stack.space) }
    }

    @Test func renameAndRecolour() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        try service.renameList(list, to: " Hétvége ")
        #expect(list.name == "Hétvége")
        try service.updateList(list, name: "Hétvége", color: "#4A90D9")
        #expect(list.color == "#4A90D9")
        #expect(throws: ServiceError.nameRequired) { try service.renameList(list, to: "") }
    }

    @Test func reorderListsPersistsOrder() throws {
        let a = try service.createList(name: "A", in: stack.space)
        let b = try service.createList(name: "B", in: stack.space)
        let c = try service.createList(name: "C", in: stack.space)
        try service.reorderLists([c, a, b])
        #expect(try service.lists(in: stack.space) == [c, a, b])
    }

    @Test func listsAreScopedToTheirSpace() throws {
        let other = try stack.makeOtherSpace()
        _ = try service.createList(name: "Itt", in: stack.space)
        _ = try service.createList(name: "Ott", in: other)
        #expect(try service.lists(in: stack.space).map(\.name) == ["Itt"])
    }

    @Test func deleteListRemovesItsItems() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        try service.addItem(to: list, customName: "Kenyér")
        try service.addItem(to: list, customName: "Tej")
        try service.deleteList(list)
        #expect(try stack.count(ShoppingList.self) == 0)
        #expect(try stack.count(ShoppingListItem.self) == 0)
    }

    // MARK: Items

    @Test func addItemWithCustomName() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "  Kenyér ", quantity: 2, note: " friss ")
        #expect(item.customName == "Kenyér")
        #expect(item.product == nil)
        #expect(item.quantity == 2)
        #expect(item.unit == .piece)
        #expect(item.note == "friss")
        #expect(item.isPurchased == false)
        #expect(item.shoppingList == list)
        #expect(ShoppingService.displayName(of: item) == "Kenyér")
        #expect(!stack.context.hasChanges)
    }

    @Test func addItemWithProductUsesItsDefaultUnit() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, product: milk)
        #expect(item.product == milk)
        #expect(item.unit == .liter)
        #expect(item.customName == nil)
        #expect(ShoppingService.displayName(of: item) == "Tej")
        let millilitres = try service.addItem(to: list, product: milk, unit: .milliliter)
        #expect(millilitres.unit == .milliliter)
    }

    @Test func addItemValidates() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        #expect(throws: ServiceError.nameRequired) { _ = try service.addItem(to: list, customName: "  ") }
        #expect(throws: ServiceError.nameRequired) { _ = try service.addItem(to: list) }
        #expect(throws: ServiceError.quantityMustBePositive) {
            _ = try service.addItem(to: list, customName: "Tej", quantity: 0)
        }
        #expect(throws: ServiceError.quantityMustBePositive) {
            _ = try service.addItem(to: list, customName: "Tej", quantity: -1)
        }
        let foreign = try stack.makeProduct("Idegen", in: try stack.makeOtherSpace())
        #expect(throws: ServiceError.notFound) { _ = try service.addItem(to: list, product: foreign) }
        #expect(try stack.count(ShoppingListItem.self) == 0)
    }

    @Test func newItemsGoToTheEnd() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let a = try service.addItem(to: list, customName: "A")
        let b = try service.addItem(to: list, customName: "B")
        let c = try service.addItem(to: list, customName: "C")
        #expect(try service.unpurchasedItems(in: list) == [a, b, c])
    }

    @Test func updateItemValidatesAndSaves() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let spar = try stack.makeStore("Spar")
        let item = try service.addItem(to: list, customName: "Kenyér")
        let deadline = stack.now.date.addingTimeInterval(86_400)
        try service.updateItem(item, product: nil, customName: "Rozskenyér", quantity: 2, unit: .piece,
                               note: "", deadline: deadline, shoppingLocation: spar)
        #expect(item.customName == "Rozskenyér")
        #expect(item.quantity == 2)
        #expect(item.note == nil)
        #expect(item.deadline == deadline)
        #expect(item.shoppingLocation == spar)
        #expect(!stack.context.hasChanges)
        #expect(throws: ServiceError.quantityMustBePositive) {
            try service.updateItem(item, product: nil, customName: "X", quantity: 0, unit: .piece,
                                   note: nil, deadline: nil, shoppingLocation: nil)
        }
        #expect(throws: ServiceError.nameRequired) {
            try service.updateItem(item, product: nil, customName: " ", quantity: 1, unit: .piece,
                                   note: nil, deadline: nil, shoppingLocation: nil)
        }
        let foreignStore = try stack.makeStore("Idegen", in: try stack.makeOtherSpace())
        #expect(throws: ServiceError.notFound) {
            try service.updateItem(item, product: nil, customName: "X", quantity: 1, unit: .piece,
                                   note: nil, deadline: nil, shoppingLocation: foreignStore)
        }
        #expect(item.customName == "Rozskenyér")
        #expect(item.shoppingLocation == spar)
    }

    @Test func deleteItem() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "Kenyér")
        try service.deleteItem(item)
        #expect(try service.items(in: list).isEmpty)
    }

    @Test func reorderItems() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let a = try service.addItem(to: list, customName: "A")
        let b = try service.addItem(to: list, customName: "B")
        let c = try service.addItem(to: list, customName: "C")
        try service.reorderItems([c, a, b])
        #expect(try service.unpurchasedItems(in: list) == [c, a, b])
        #expect(!stack.context.hasChanges)
    }

    // MARK: Purchase

    @Test func togglePurchasedSetsAndClearsPurchasedAt() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let item = try service.addItem(to: list, customName: "Kenyér")
        stack.now.advance(seconds: 60)
        try service.togglePurchased(item)
        #expect(item.isPurchased)
        #expect(item.purchasedAt == stack.now.date)
        #expect(item.updatedAt == stack.now.date)
        #expect(!stack.context.hasChanges)
        try service.togglePurchased(item)
        #expect(!item.isPurchased)
        #expect(item.purchasedAt == nil)
    }

    @Test func purchasedAndUnpurchasedAreSeparatedAndOrdered() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let a = try service.addItem(to: list, customName: "A")
        let b = try service.addItem(to: list, customName: "B")
        let c = try service.addItem(to: list, customName: "C")
        let d = try service.addItem(to: list, customName: "D")
        try service.togglePurchased(b)
        stack.now.advance(seconds: 10)
        try service.togglePurchased(d)
        #expect(try service.unpurchasedItems(in: list) == [a, c])
        #expect(try service.purchasedItems(in: list) == [d, b])     // most recent first
        try service.togglePurchased(b)
        #expect(try service.unpurchasedItems(in: list) == [a, b, c]) // back in its old place
    }

    @Test func clearPurchasedDeletesOnlyPurchased() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        let keep = try service.addItem(to: list, customName: "Marad")
        let gone = try service.addItem(to: list, customName: "Megvan")
        try service.togglePurchased(gone)
        #expect(try service.clearPurchased(in: list) == 1)
        #expect(try service.items(in: list) == [keep])
    }

    // MARK: Barcode and suggestions

    @Test func knownBarcodeAddsTheProductAndThenIncrements() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter, barcode: "5998200110039")
        let list = try service.createList(name: "Heti", in: stack.space)

        guard case .added(let item) = try service.addFromBarcode(" 5998200110039 ", to: list) else {
            Issue.record("expected .added")
            return
        }
        #expect(item.product == milk)
        #expect(item.quantity == 1)
        guard case .added(let again) = try service.addFromBarcode("5998200110039", to: list) else {
            Issue.record("expected .added")
            return
        }
        #expect(again == item)
        #expect(item.quantity == 2)
        #expect(try service.items(in: list).count == 1)
    }

    @Test func unknownBarcodeIsReturnedForTheUI() throws {
        let list = try service.createList(name: "Heti", in: stack.space)
        _ = try stack.makeProduct("Idegen", barcode: "111", in: try stack.makeOtherSpace())
        guard case .unknown(let code) = try service.addFromBarcode("111", to: list) else {
            Issue.record("expected .unknown")
            return
        }
        #expect(code == "111")
        #expect(try service.items(in: list).isEmpty)
    }

    @Test func suggestionsRankPrefixThenFavouritesThenName() throws {
        try stack.makeProduct("Kakaós csiga")
        try stack.makeProduct("Tejföl")
        try stack.makeProduct("Tej", favorite: true)
        try stack.makeProduct("Kókusztej")
        try stack.makeProduct("Tejszín")
        _ = try stack.makeProduct("Tejpor", in: try stack.makeOtherSpace())

        let names = try service.productSuggestions(matching: "tej", in: stack.space).map(\.name)
        #expect(names == ["Tej", "Tejföl", "Tejszín", "Kókusztej"])
        #expect(try service.productSuggestions(matching: "TÉJ", in: stack.space).count == 4)
        #expect(try service.productSuggestions(matching: "tej", in: stack.space, limit: 2).count == 2)
        #expect(try service.productSuggestions(matching: "  ", in: stack.space).isEmpty)
    }
}
