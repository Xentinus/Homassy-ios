import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Purchase form model")
struct PurchaseFormModelTests {
    let stack: ShoppingTestStack
    let locations: ShoppingLocationService
    let locale = Locale(identifier: "en_US")

    init() throws {
        stack = try ShoppingTestStack()
        locations = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user)
    }

    private func makeModel(_ item: ShoppingListItem) -> PurchaseFormModel {
        PurchaseFormModel(item: item, shopping: stack.service, inventory: stack.inventory, locations: locations,
                          pending: stack.pending, locale: locale)
    }

    @Test func startsWithTheFullAmountTheItemStoreAndTheLastLocation() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let spar = try stack.makeStore("Spar")
        let fridge = try stack.makeLocation("Hűtő")
        try stack.inventory.addStock(product: milk, quantity: 1, unit: .liter, expiresAt: nil, purchasedAt: nil,
                                     price: nil, currency: nil, storageLocation: fridge, shoppingLocation: nil)
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, product: milk, quantity: Decimal(string: "1.5")!,
                                             shoppingLocation: spar)

        let model = makeModel(item)
        #expect(model.itemName == "Tej")
        #expect(model.quantityText == "1.5")
        #expect(model.quantity == Decimal(string: "1.5")!)
        #expect(model.storeName == "Spar")
        #expect(model.storageLocationID == fridge.publicId)
        #expect(model.storageOptions.map(\.name) == ["Hűtő"])
        #expect(model.currency == "HUF")
        #expect(!model.showsKeepRemainder)
        #expect(model.listedText == Quantity.format(Decimal(string: "1.5")!, unit: .liter, locale: locale))
    }

    @Test func keepToggleShowsOnlyBelowTheListedAmount() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Alma", quantity: 3)
        let model = makeModel(item)
        model.quantityText = "1"
        #expect(model.showsKeepRemainder)
        #expect(model.remainderText == Quantity.format(2, unit: .piece, locale: locale))
        model.quantityText = "4"
        #expect(!model.showsKeepRemainder)
        model.quantityText = "abc"
        #expect(!model.canPurchase)
    }

    @Test func suggestionFillsOnlyAnEmptyStore() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let spar = try stack.makeStore("Spar")
        let withStore = makeModel(try stack.service.addItem(to: list, customName: "A", shoppingLocation: spar))
        withStore.applySuggestion(.place(StoreSamples.aldiNyugati, distance: 40))
        #expect(withStore.storeName == "Spar")
        #expect(withStore.suggestedDistance == nil)

        let empty = makeModel(try stack.service.addItem(to: list, customName: "B"))
        empty.applySuggestion(.place(StoreSamples.aldiNyugati, distance: 40))
        #expect(empty.storeName == "Aldi Nyugati")
        #expect(empty.suggestedDistance == 40)

        let picked = makeModel(try stack.service.addItem(to: list, customName: "C"))
        picked.setStore(nil)
        picked.applySuggestion(.place(StoreSamples.aldiNyugati, distance: 40))
        #expect(picked.storeName == nil)
    }

    @Test func purchaseStoresTheSuggestedPlaceAndAddsStock() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Alma", quantity: 3)
        let model = makeModel(item)
        model.applySuggestion(.place(StoreSamples.aldiNyugati, distance: 40))
        model.quantityText = "2"
        model.keepRemainder = true
        model.priceText = "1299.5"
        model.hasExpiry = true

        let action = model.purchase()
        #expect(model.errorMessage == nil)
        guard let action else { return }
        try action.commit()
        let stock = try #require(try stack.inventory.items(in: stack.space).first)
        #expect(stock.quantity == 2)
        #expect(stock.price == Decimal(string: "1299.5")!)
        #expect(stock.expiresAt == model.expiresAt)
        #expect(stock.shoppingLocation?.mapItemIdentifier == StoreSamples.aldiNyugati.mapItemIdentifier)
        #expect(item.quantity == 1)
        #expect(try stack.service.items(in: list) == [item])
    }

    @Test func invalidInputGivesAnErrorAndNoAction() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let model = makeModel(try stack.service.addItem(to: list, customName: "Alma"))
        model.quantityText = "0"
        #expect(model.purchase() == nil)
        #expect(model.errorMessage != nil)
        model.quantityText = "1"
        model.priceText = "sok"
        #expect(model.purchase() == nil)
        #expect(model.errorMessage != nil)
        #expect(try stack.count(InventoryItem.self) == 0)
    }

    @Test func switchingInventoryOffOnlyRemovesTheItem() throws {
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let item = try stack.service.addItem(to: list, customName: "Alma")
        let model = makeModel(item)
        #expect(model.addToInventory)
        model.addToInventory = false
        model.priceText = "sok"                                  // ignored without inventory
        model.applySuggestion(.place(StoreSamples.aldiNyugati, distance: 40))
        let action = try #require(model.purchase())
        try action.commit()
        #expect(try stack.service.items(in: list).isEmpty)
        #expect(try stack.count(InventoryItem.self) == 0)
        #expect(try stack.count(ShoppingLocation.self) == 0)     // the suggested place is not stored either
    }

    @Test func withoutInventoryAProductStillRecordsStoreAndPrice() throws {
        let milk = try stack.makeProduct("Tej", unit: .liter)
        let list = try stack.service.createList(name: "Heti", in: stack.space)
        let model = makeModel(try stack.service.addItem(to: list, product: milk))
        model.addToInventory = false
        #expect(model.recordsPurchase)
        model.applySuggestion(.place(StoreSamples.aldiNyugati, distance: 40))
        model.priceText = "450"
        try #require(model.purchase()).commit()
        let record = try #require(try stack.context.fetch(NSFetchRequest<PurchaseRecord>(entityName: "PurchaseRecord")).first)
        #expect(record.price == 450)
        #expect(record.shoppingLocation?.name == "Aldi Nyugati")
        #expect(try stack.count(InventoryItem.self) == 0)
    }
}
