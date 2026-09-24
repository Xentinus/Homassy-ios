import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("StockFormModel")
struct StockFormModelTests {
    static let hu = Locale(identifier: "hu_HU")

    func form(_ env: ServiceTestEnvironment, productID: UUID? = nil) -> StockFormModel {
        StockFormModel(mode: .add(env.personal, productID: productID), inventory: env.inventoryService(),
                       products: env.productService(), storage: env.storageService(), locale: Self.hu)
    }

    @Test func defaultsAndProductUnit() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", unit: .liter)
        try await env.makeProduct("Bread")
        let form = form(env)
        #expect(form.productOptions.map(\.name) == ["Bread", "Milk"])
        #expect(form.quantityText == "1" && form.hasExpiry && form.currency == "HUF")
        #expect(!form.canSave && !form.isEditing)
        form.productID = milk.publicId
        #expect(form.unit == .liter && form.canSave)
        #expect(form.targetSpace == env.personal)
    }

    @Test func savesWithLocaleDecimalsLocationAndPrice() async throws {
        let env = try ServiceTestEnvironment()
        let fridge = try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false)
        let milk = try await env.makeProduct("Milk", unit: .liter)
        let form = form(env, productID: milk.publicId)
        #expect(form.locationOptions.map(\.name) == ["Fridge"])
        form.quantityText = "1,5"
        form.locationID = fridge.publicId
        form.priceText = "459,90"
        form.purchasedAt = env.day(0)
        form.expiresAt = env.day(6)
        let item = try #require(form.save())
        #expect(item.quantity == Decimal(string: "1.5")!)
        #expect(item.unit == .liter)
        #expect(item.price == Decimal(string: "459.9")!)
        #expect(item.storageLocation == fridge && item.expiresAt == env.day(6) && item.currency == "HUF")
    }

    @Test func noExpiryStoresNil() async throws {
        let env = try ServiceTestEnvironment()
        let salt = try await env.makeProduct("Salt")
        let form = form(env, productID: salt.publicId)
        form.hasExpiry = false
        #expect(try #require(form.save()).expiresAt == nil)
    }

    @Test func validationMessages() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        let form = form(env, productID: milk.publicId)
        form.quantityText = "abc"
        #expect(form.save() == nil)
        #expect(form.quantityError == coreLocalized("form.invalidQuantity"))
        form.quantityText = "0"
        #expect(form.save() == nil)
        #expect(form.quantityError != nil)
        form.quantityText = "2"
        form.priceText = "ingyen"
        #expect(form.save() == nil)
        #expect(form.quantityError == nil && form.priceError == coreLocalized("form.invalidPrice"))
        form.priceText = ""
        form.purchasedAt = env.day(3)
        form.expiresAt = env.day(1)
        #expect(form.save() == nil)
        #expect(form.errorMessage == ServiceError.expiryBeforePurchase.errorDescription)
        #expect(try env.count(InventoryItem.self) == 0)
    }

    @Test func editLoadsAndUpdates() async throws {
        let env = try ServiceTestEnvironment()
        let eggs = try await env.makeProduct("Eggs")
        let item = try env.stock(eggs, 10, expiresInDays: 20)
        let form = StockFormModel(mode: .edit(item), inventory: env.inventoryService(), products: env.productService(),
                                  storage: env.storageService(), locale: Self.hu)
        #expect(form.isEditing && form.productID == eggs.publicId && form.quantityText == "10" && form.hasExpiry)
        form.quantityText = "8"
        #expect(form.save() == item)
        #expect(item.quantity == 8)
    }

    @Test func newlyCreatedProductIsSelected() async throws {
        let env = try ServiceTestEnvironment()
        let form = form(env)
        let paprika = try await env.makeProduct("Paprika", unit: .gram)
        form.productCreated(paprika)
        #expect(form.productID == paprika.publicId && form.unit == .gram)
        #expect(form.productOptions.map(\.name) == ["Paprika"])
    }

    @Test func messagesAreTranslated() {
        for key in ["form.invalidQuantity", "form.invalidPrice"] {
            for id in ["hu_HU", "en_US", "de_DE"] {
                #expect(CoreLocalization.lookup(key, locale: Locale(identifier: id)) != nil)
            }
        }
    }
}
