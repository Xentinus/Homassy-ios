import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("ProductListModel")
struct ProductListModelTests {
    static let hu = Locale(identifier: "hu_HU")
    static let en = Locale(identifier: "en_US")

    func model(_ env: ServiceTestEnvironment, pending: PendingDeletions = PendingDeletions(),
               canEdit: Bool = true, locale: Locale = ProductListModelTests.hu) -> ProductListModel {
        let model = ProductListModel(products: env.productService(canEdit: { _ in canEdit }),
                                     inventory: env.inventoryService(), space: env.personal,
                                     pending: pending, locale: locale)
        model.reload()
        return model
    }

    @Test func groupsAlphabeticallyWithHashLast() async throws {
        let env = try ServiceTestEnvironment()
        for name in ["alma", "Áfonya", "banán", "Kenyér", "123 cola"] { try await env.makeProduct(name) }
        let model = model(env)
        #expect(model.sections.map(\.id) == ["A", "B", "K", "#"])
        #expect(model.sections[0].cards.map(\.name) == ["Áfonya", "alma"])
        #expect(!model.isFiltering)
    }

    @Test func cardCarriesProductFields() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Milk", brand: "Mizo", category: "Dairy", barcode: "5991234567890", unit: .liter)
        let card = try #require(model(env).sections.first?.cards.first)
        #expect(card.name == "Milk" && card.brand == "Mizo" && card.barcode == "5991234567890")
        #expect(!card.isFavorite)
        #expect(card.stockText == nil && card.expiryText == nil && card.expiryLevel == .none)
    }

    @Test("The stock line adds up open items per unit, the expiry line comes from the first to expire")
    func stockAndExpiry() async throws {
        let env = try ServiceTestEnvironment()
        let (pantry, fridge) = (try env.storageService().create(in: env.personal, name: "Pantry", color: nil, isFreezer: false),
                                try env.storageService().create(in: env.personal, name: "Fridge", color: nil, isFreezer: false))
        let eggs = try await env.makeProduct("Eggs")
        try env.stock(eggs, 2, location: pantry, expiresInDays: 1)
        try env.stock(eggs, 10, location: fridge, expiresInDays: 20)
        let milk = try await env.makeProduct("Milk", unit: .liter)
        try env.stock(milk, 1, expiresInDays: 30)
        try env.stock(milk, 1, expiresInDays: -2)
        let used = try env.stock(try await env.makeProduct("Salt", unit: .gram), 500)
        try env.inventoryService().markUsedUp(used)

        let cards = Dictionary(uniqueKeysWithValues: model(env).sections.flatMap(\.cards).map { ($0.name, $0) })
        #expect(cards["Eggs"]?.stockText == "12\u{00A0}db")
        #expect(cards["Eggs"]?.expiryLevel == .critical)
        #expect(cards["Eggs"]?.expiryText == "Holnap lejár")
        #expect(cards["Milk"]?.stockText == "2 × 1\u{00A0}l")
        #expect(cards["Milk"]?.expiryLevel == .expired)
        #expect(cards["Milk"]?.expiryText == "2 napja lejárt")
        #expect(cards["Salt"]?.stockText == nil)
    }

    @Test func mixedUnitsAreListedSeparately() async throws {
        let env = try ServiceTestEnvironment()
        let rice = try await env.makeProduct("Rice", unit: .kilogram)
        try env.stock(rice, 1)
        try env.inventoryService().addStock(product: rice, quantity: 500, unit: .gram, expiresAt: nil, purchasedAt: nil,
                                            price: nil, currency: nil, storageLocation: nil, shoppingLocation: nil)
        let card = try #require(model(env, locale: Self.en).sections.first?.cards.first)
        #expect(card.stockText == "500\u{00A0}g, 1\u{00A0}kg")
    }

    @Test func searchAndCategoryFilter() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Milk", category: "Dairy")
        try await env.makeProduct("Eggs", category: "Dairy")
        try await env.makeProduct("Bread", category: "Bakery")
        let model = model(env)
        #expect(model.categories == ["Bakery", "Dairy"])

        model.searchText = "egg"
        #expect(model.sections.flatMap(\.cards).map(\.name) == ["Eggs"])
        #expect(model.isFiltering)

        model.searchText = ""
        model.selectedCategory = "Dairy"
        #expect(model.sections.flatMap(\.cards).map(\.name) == ["Eggs", "Milk"])

        model.searchText = "bread"
        #expect(model.sections.isEmpty)

        model.searchText = ""
        model.selectedCategory = nil
        #expect(model.sections.flatMap(\.cards).count == 3)
    }

    @Test("A product deleted from the detail disappears while its undo window is open")
    func pendingDeletionHidesTheCard() async throws {
        let env = try ServiceTestEnvironment()
        let bread = try await env.makeProduct("Bread")
        try await env.makeProduct("Milk")
        let pending = PendingDeletions()
        let model = model(env, pending: pending)
        let action = try env.productService().deletion(of: bread, pending: pending)
        #expect(model.sections.flatMap(\.cards).map(\.name) == ["Milk"])
        action.revert()
        #expect(model.sections.flatMap(\.cards).map(\.name) == ["Bread", "Milk"])
    }

    @Test func readOnlyIsReported() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Bread")
        #expect(!model(env, canEdit: false).canEdit)
    }
}

@MainActor
@Suite("ProductListModel barcode search")
struct ProductListBarcodeSearchTests {
    func model(_ env: ServiceTestEnvironment) -> ProductListModel {
        let model = ProductListModel(products: env.productService(), inventory: env.inventoryService(),
                                     space: env.personal, pending: PendingDeletions(), locale: Locale(identifier: "en_US"))
        model.reload()
        return model
    }

    @Test("A scanned code finds the product, also across UPC-A and EAN-13")
    func knownCode() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Milk", barcode: "5991234567890")
        try await env.makeProduct("Chips", barcode: "012345678905")
        let model = model(env)
        model.searchBarcode("0012345678905", symbology: .ean13)
        #expect(model.sections.flatMap(\.cards).map(\.name) == ["Chips"])
        #expect(model.unknownBarcode == nil)
        model.searchBarcode("5991234567890", symbology: .ean13)
        #expect(model.sections.flatMap(\.cards).map(\.name) == ["Milk"])
    }

    @Test("An unknown code shows no results and remembers the code for a new product until the text changes")
    func unknownCode() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Milk", barcode: "5991234567890")
        let model = model(env)
        model.searchBarcode("4000000000009", symbology: .ean13)
        #expect(model.sections.isEmpty)
        #expect(model.unknownBarcode == "4000000000009")
        #expect(model.searchText == "4000000000009")
        model.searchText = "mi"
        #expect(model.unknownBarcode == nil)
        #expect(model.sections.flatMap(\.cards).map(\.name) == ["Milk"])
    }
}
