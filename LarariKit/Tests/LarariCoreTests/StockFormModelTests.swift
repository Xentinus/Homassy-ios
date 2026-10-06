import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("StockFormModel")
struct StockFormModelTests {
    static let hu = Locale(identifier: "hu_HU")

    func locations(_ env: ServiceTestEnvironment) -> ShoppingLocationService {
        ShoppingLocationService(spaceStore: env.spaceStore, context: env.context, userRecordName: ServiceTestEnvironment.user)
    }

    func form(_ env: ServiceTestEnvironment, productID: UUID? = nil) -> StockFormModel {
        StockFormModel(mode: .add(env.personal, productID: productID), inventory: env.inventoryService(),
                       products: env.productService(), storage: env.storageService(), locations: locations(env),
                       locale: Self.hu)
    }

    func corner(_ env: ServiceTestEnvironment) throws -> ShoppingLocation {
        try locations(env).upsert(StoreResult(mapItemIdentifier: "I-CORNER", name: "Corner", latitude: 47.5,
                                              longitude: 19.05), in: env.personal)
    }

    @Test func defaultsAndPickingAProduct() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let form = form(env)
        #expect(!form.canSave && !form.isEditing && !form.hasProduct)
        #expect(form.lots.lotCount == 1 && form.lots.lots[0].quantityText == "1" && form.lots.allowsMultiple)
        #expect(form.lots.lots[0].expiresAt == env.day(7))
        #expect(form.currency == "HUF" && form.purchasedAt == env.day(0))
        form.setProduct(milk.publicId)
        #expect(form.unit == .liter && form.canSave && form.productName == "Milk")
        #expect(form.targetSpace == env.personal)
    }

    @Test func theProductsLastLocationIsTheDefault() async throws {
        let env = try ServiceTestEnvironment()
        let fridge = try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let milk = try await env.makeProduct("Milk")
        try env.stock(milk, 1, location: fridge)
        #expect(form(env, productID: milk.publicId).lots.lots[0].storageLocationID == fridge.publicId)
        let picked = form(env)
        picked.setProduct(milk.publicId)
        #expect(picked.lots.lots[0].storageLocationID == fridge.publicId)
    }

    @Test func pickingAnotherProductResetsTheDefaultLocation() async throws {
        let env = try ServiceTestEnvironment()
        let freezer = try env.storageService().create(in: env.personal, name: "Freezer", color: nil, isFreezer: true)
        let peas = try await env.makeProduct("Peas")
        let salt = try await env.makeProduct("Salt")
        try env.stock(peas, 1, location: freezer)
        let form = form(env)
        form.setProduct(peas.publicId)
        #expect(form.lots.lots[0].storageLocationID == freezer.publicId)
        form.setProduct(salt.publicId)
        #expect(form.lots.lots[0].storageLocationID == nil, "salt has no location history")
    }

    @Test func aHandPickedLocationSurvivesAnotherProduct() async throws {
        let env = try ServiceTestEnvironment()
        let freezer = try env.storageService().create(in: env.personal, name: "Freezer", color: nil, isFreezer: true)
        let pantry = try env.storageService().create(in: env.personal, name: "Pantry", color: nil, isFreezer: false)
        let fridge = try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let peas = try await env.makeProduct("Peas")
        let milk = try await env.makeProduct("Milk")
        try env.stock(peas, 1, location: freezer)
        try env.stock(milk, 1, location: fridge)
        let form = form(env)
        form.setProduct(peas.publicId)
        form.lots.lots[0].storageLocationID = pantry.publicId
        form.setProduct(milk.publicId)
        #expect(form.lots.lots[0].storageLocationID == pantry.publicId)
    }

    @Test func setProductIsIgnoredWhileEditingAndForAnotherSpace() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let item = try env.stock(eggs, 10)
        let edit = StockFormModel(mode: .edit(item), inventory: env.inventoryService(), products: env.productService(),
                                  storage: env.storageService(), locations: locations(env), locale: Self.hu)
        edit.setProduct(milk.publicId)
        #expect(edit.productID == eggs.publicId && edit.unit == .piece)
        let foreign = try await env.makeProduct("Foreign", in: try env.makeHousehold(), unit: .liter)
        let add = form(env)
        add.setProduct(foreign.publicId)
        #expect(add.productID == nil && add.unit == .piece && !add.hasProduct)
    }

    @Test func twoLotsSplitThePriceAndShareTheStore() async throws {
        let env = try ServiceTestEnvironment()
        let fridge = try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let garage = try env.storageService().create(in: env.personal, name: "Garage", color: nil, isFreezer: false)
        let milk = try await env.makeProduct("Milk")
        let store = try corner(env)
        let form = form(env, productID: milk.publicId)
        form.lots.lots[0].storageLocationID = fridge.publicId
        #expect(form.priceShares == nil, "no split line with one lot")
        form.lots.addLot()
        form.lots.lots[1].storageLocationID = garage.publicId
        form.lots.lots[1].expiresAt = env.day(14)
        form.priceText = "900"
        form.store.choose(store.publicId)
        #expect(form.priceShares == [450, 450])
        #expect(form.priceSplitText != nil)
        let items = try #require(form.save())
        #expect(items.map(\.storageLocation) == [fridge, garage])
        #expect(items.map(\.expiresAt) == [env.day(7), env.day(14)])
        #expect(items.map(\.price) == [450, 450])
        #expect(items.allSatisfy { $0.shoppingLocation == store && $0.purchaseRecordSet.first?.shoppingLocation == store })
    }

    @Test func noExpiryStoresNil() async throws {
        let env = try ServiceTestEnvironment()
        let salt = try await env.makeProduct("Salt")
        let form = form(env, productID: salt.publicId)
        form.lots.lots[0].expiresAt = nil
        #expect(try #require(form.save()).first?.expiresAt == nil)
    }

    @Test func validationMessages() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let form = form(env, productID: milk.publicId)
        form.lots.lots[0].quantityText = "abc"
        #expect(form.save() == nil)
        #expect(form.lots.quantityErrors[form.lots.lots[0].id] == coreLocalized("form.invalidQuantity"))
        form.lots.lots[0].quantityText = "2"
        form.priceText = "ingyen"
        #expect(form.save() == nil)
        #expect(form.priceError == coreLocalized("form.invalidPrice"))
        form.priceText = ""
        form.purchasedAt = env.day(3)
        form.lots.lots[0].expiresAt = env.day(1)
        #expect(form.save() == nil)
        #expect(form.priceError == nil && form.errorMessage == ServiceError.expiryBeforePurchase.errorDescription)
        #expect(try env.count(InventoryItem.self) == 0)
    }

    @Test func editKeepsOneLotAndCanChangeTheStore() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 10, expiresInDays: 20)
        let store = try corner(env)
        let form = StockFormModel(mode: .edit(item), inventory: env.inventoryService(), products: env.productService(),
                                  storage: env.storageService(), locations: locations(env), locale: Self.hu)
        #expect(form.isEditing && form.productID == eggs.publicId && form.lots.lots[0].quantityText == "10")
        #expect(form.lots.lots[0].expiresAt == env.day(20) && !form.lots.allowsMultiple)
        form.lots.lots[0].quantityText = "8"
        form.store.choose(store.publicId)
        #expect(form.save() == [item])
        #expect(item.quantity == 8 && item.shoppingLocation == store)
    }

    @Test func messagesAreTranslated() {
        for key in ["form.invalidQuantity", "form.invalidPrice"] {
            for id in ["hu_HU", "en_US", "de_DE"] {
                #expect(CoreLocalization.lookup(key, locale: Locale(identifier: id)) != nil)
            }
        }
    }
}
