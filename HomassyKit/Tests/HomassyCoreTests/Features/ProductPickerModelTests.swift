import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Product picker")
struct ProductPickerModelTests {
    func picker(_ env: ServiceTestEnvironment, pending: PendingDeletions = PendingDeletions()) -> ProductPickerModel {
        ProductPickerModel(space: env.personal, products: env.productService(), inventory: env.inventoryService(),
                           pending: pending, locale: Locale(identifier: "hu_HU"))
    }

    @Test func sectionsAreLettersWithTheOthersLast() async throws {
        let env = try ServiceTestEnvironment()
        for name in ["Tej", "alma", "Ásványvíz", "7Up", "Banán"] { try await env.makeProduct(name) }
        let model = picker(env)
        #expect(model.sections.map(\.id) == ["A", "B", "T", "#"])
        #expect(model.sections[0].products.map(\.name) == ["alma", "Ásványvíz"])
        #expect(!model.isSearching && model.canCreate)
    }

    @Test func recentsFollowTheNewestStockAndStopAtFive() async throws {
        let env = try ServiceTestEnvironment()
        var products: [Product] = []
        for name in ["A1", "B2", "C3", "D4", "E5", "F6"] { products.append(try await env.makeProduct(name)) }
        for (offset, product) in products.enumerated() {
            try env.stock(product, 1).createdAt = env.day(offset)
        }
        try env.stock(products[0], 1).createdAt = env.day(10)
        try env.context.save()
        let model = picker(env)
        #expect(model.recents.map(\.name) == ["A1", "F6", "E5", "D4", "C3"])
        model.searchText = "a"
        #expect(model.recents.isEmpty)
    }

    @Test func searchIgnoresCaseAndAccentsAndOffersANewProduct() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Kefír", category: "Tejtermék")
        try await env.makeProduct("Kefires lepény")
        let model = picker(env)
        model.searchText = "kefir"
        #expect(model.isSearching)
        #expect(model.sections.flatMap(\.products).map(\.name) == ["Kefír", "Kefires lepény"])
        #expect(model.createCandidate == nil, "Kefír matches apart from the accent")
        model.searchText = " kef "
        #expect(model.createCandidate == "kef")
        model.searchText = "  "
        #expect(model.createCandidate == nil && !model.isSearching)
    }

    @Test func subtitleIsTheBrandElseTheCategory() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Tej", brand: "Mizo", category: "Tejtermék")
        try await env.makeProduct("Liszt", category: "Alapanyag")
        try await env.makeProduct("Só")
        #expect(picker(env).sections.flatMap(\.products).map(\.subtitle) == ["Alapanyag", nil, "Mizo"])
    }

    @Test func pendingDeletionsAreHidden() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Tej")
        try await env.makeProduct("Liszt")
        let pending = PendingDeletions()
        pending.hide(milk.publicId)
        #expect(picker(env, pending: pending).sections.flatMap(\.products).map(\.name) == ["Liszt"])
    }

    @Test func aScannedCodeFindsTheProduct() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Tej", barcode: "5998200110039")
        #expect(picker(env).route(barcode: "5998200110039") == .known(milk))
        #expect(picker(env).route(barcode: "4006381333931") != .known(milk))
    }

    @Test func aNewProductCanStartWithTheSearchedName() throws {
        let env = try ServiceTestEnvironment()
        let form = ProductFormModel(mode: .create(env.personal, barcode: nil, name: "Kefír"), service: env.productService())
        #expect(form.draft.name == "Kefír")
        #expect(ProductFormModel(mode: .create(env.personal, barcode: "123"), service: env.productService()).draft.name == "")
    }
}
