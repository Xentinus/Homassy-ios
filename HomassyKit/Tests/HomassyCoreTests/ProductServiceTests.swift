import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("ProductService")
struct ProductServiceTests {
    @Test func createTrimsAndStores() async throws {
        let env = try ServiceTestEnvironment()
        let product = try await env.productService().create(in: env.personal, draft: ProductDraft(
            name: "  Milk ", brand: " Mizo ", category: "  ", barcode: " 5991234567890 ",
            defaultUnit: .liter, isFavorite: true, notes: "", url: " tej.hu/mizo "))
        #expect(product.name == "Milk")
        #expect(product.brand == "Mizo")
        #expect(product.category == nil)
        #expect(product.barcode == "5991234567890")
        #expect(product.notes == nil)
        #expect(product.url == "https://tej.hu/mizo")
        #expect(product.defaultUnit == .liter)
        #expect(product.isFavorite)
        #expect(product.space == env.personal)
        #expect(product.createdBy == ServiceTestEnvironment.user)
        #expect(!env.context.hasChanges)
    }

    @Test("Blank names are rejected", arguments: ["", "   ", "\n\t"])
    func nameRequired(name: String) async throws {
        let env = try ServiceTestEnvironment()
        await #expect(throws: ServiceError.nameRequired) {
            _ = try await env.productService().create(in: env.personal, draft: ProductDraft(name: name))
        }
        #expect(try env.count(Product.self) == 0)
    }

    @Test func createProcessesImage() async throws {
        let env = try ServiceTestEnvironment()
        let product = try await env.makeProduct("Bread", image: TestImages.jpeg(width: 4000, height: 3000))
        let image = try #require(product.image)
        let size = try #require(TestImages.pixelSize(of: image))
        #expect(max(size.width, size.height) == 800)
    }

    @Test func unreadableImageInsertsNothing() async throws {
        let env = try ServiceTestEnvironment()
        await #expect(throws: ImageProcessor.Failure.undecodable) {
            _ = try await env.makeProduct("Bread", image: Data("nope".utf8))
        }
        #expect(try env.count(Product.self) == 0)
    }

    @Test func readOnlySpaceIsEnforced() async throws {
        let env = try ServiceTestEnvironment()
        let product = try await env.makeProduct("Milk")
        let readOnly = env.productService(canEdit: { _ in false })
        await #expect(throws: ServiceError.readOnlySpace) {
            _ = try await readOnly.create(in: env.personal, draft: ProductDraft(name: "Eggs"))
        }
        await #expect(throws: ServiceError.readOnlySpace) {
            try await readOnly.update(product, with: ProductDraft(name: "Oat milk"))
        }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.delete(product) }
        #expect(throws: ServiceError.readOnlySpace) { try readOnly.deletion(of: product, pending: PendingDeletions()) }
        #expect(product.name == "Milk")
        #expect(try env.count(Product.self) == 1)
    }

    @Test func updateChangesFieldsAndStamps() async throws {
        let env = try ServiceTestEnvironment()
        let product = try await env.makeProduct("Milk", category: "Dairy")
        var draft = ProductDraft(product: product)
        draft.name = "Oat milk"
        draft.category = "Drinks"
        draft.url = "http://example.com/oat"
        try await env.productService(user: ServiceTestEnvironment.otherUser).update(product, with: draft)
        #expect(product.name == "Oat milk")
        #expect(product.category == "Drinks")
        #expect(product.url == "http://example.com/oat")
        #expect(product.createdBy == ServiceTestEnvironment.user)
        #expect(product.updatedBy == ServiceTestEnvironment.otherUser)
        #expect(!env.context.hasChanges)
    }

    @Test func updateRejectsBlankName() async throws {
        let env = try ServiceTestEnvironment()
        let product = try await env.makeProduct("Milk")
        await #expect(throws: ServiceError.nameRequired) {
            try await env.productService().update(product, with: ProductDraft(name: " "))
        }
        #expect(product.name == "Milk")
    }

    @Test func updateKeepsUnchangedImageBytesAndCanRemoveIt() async throws {
        let env = try ServiceTestEnvironment()
        let product = try await env.makeProduct("Bread", image: TestImages.jpeg(width: 1200, height: 900))
        let stored = try #require(product.image)

        var draft = ProductDraft(product: product)
        draft.name = "Rye bread"
        try await env.productService().update(product, with: draft)
        #expect(product.image == stored)

        draft.imageData = nil
        try await env.productService().update(product, with: draft)
        #expect(product.image == nil)
    }

    @Test func deleteRemovesItemsAndLogs() async throws {
        let env = try ServiceTestEnvironment()
        let product = try await env.makeProduct("Milk")
        let item = env.spaceStore.insert(InventoryItem.self, in: env.personal, by: ServiceTestEnvironment.user)
        item.product = product
        item.quantity = 2
        item.unit = .liter
        let log = env.spaceStore.insert(ConsumptionLog.self, in: env.personal, by: ServiceTestEnvironment.user)
        log.inventoryItem = item
        log.quantity = 1
        log.remaining = 2
        log.consumedAt = .now
        try env.context.save()

        try env.productService().delete(product)
        #expect(try env.count(Product.self) == 0)
        #expect(try env.count(InventoryItem.self) == 0)
        #expect(try env.count(ConsumptionLog.self) == 0)
        #expect(throws: ServiceError.notFound) { try env.productService().delete(product) }
    }

    @Test func barcodeLookupIsExactAndPerSpace() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let milk = try await env.makeProduct("Milk", barcode: "5991234567890")
        try await env.makeProduct("Other milk", in: home, barcode: "4000000000009")
        let service = env.productService()
        #expect(try service.product(barcode: "5991234567890", in: env.personal) == milk)
        #expect(try service.product(barcode: " 5991234567890\n", in: env.personal) == milk)
        #expect(try service.product(barcode: "599123456789", in: env.personal) == nil)
        #expect(try service.product(barcode: "4000000000009", in: env.personal) == nil)
        #expect(try service.product(barcode: "", in: env.personal) == nil)
    }

    @Test func searchIsCaseAndDiacriticInsensitive() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        try await env.makeProduct("Túró Rudi", brand: "Pöttyös", category: "Tejtermék")
        try await env.makeProduct("alma", category: "Gyümölcs", barcode: "5990000000001")
        try await env.makeProduct("Kenyér")
        try await env.makeProduct("Túró", in: home)
        let service = env.productService()
        func names(_ query: String) throws -> [String] { try service.search(query, in: env.personal).map(\.name) }

        #expect(try names("turo") == ["Túró Rudi"])
        #expect(try names("POTTY") == ["Túró Rudi"])
        #expect(try names("tejterm") == ["Túró Rudi"])
        #expect(try names("gyumolcs") == ["alma"])
        #expect(try names("59900") == ["alma"])
        #expect(try names("  ") == ["alma", "Kenyér", "Túró Rudi"])
        #expect(try names("xyz").isEmpty)
        #expect(try service.products(in: env.personal).map(\.name) == ["alma", "Kenyér", "Túró Rudi"])
    }

    @Test func categoriesAreDistinctAndSorted() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Milk", category: "Dairy")
        try await env.makeProduct("Cheese", category: "dairy ")
        try await env.makeProduct("Bread", category: " Bakery")
        try await env.makeProduct("Soap", category: "")
        try await env.makeProduct("Salt")
        #expect(try env.productService().categories(in: env.personal) == ["Bakery", "Dairy"])
    }

    @Test func publicIdLookup() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk")
        #expect(try env.productService().product(publicId: milk.publicId) == milk)
        #expect(try env.productService().product(publicId: UUID()) == nil)
    }

    @Test("Links are trimmed, get https:// when they have no scheme, and blank removes them")
    func urlNormalisation() async throws {
        let env = try ServiceTestEnvironment()
        let service = env.productService()
        let product = try await service.create(in: env.personal, draft: ProductDraft(name: "Milk", url: "  "))
        #expect(product.url == nil)
        var draft = ProductDraft(product: product)
        draft.url = "https://www.mizo.hu/termekek?id=12"
        try await service.update(product, with: draft)
        #expect(product.url == "https://www.mizo.hu/termekek?id=12")
        draft.url = ""
        try await service.update(product, with: draft)
        #expect(product.url == nil)
    }

    @Test("Invalid links are rejected", arguments: ["not a link", "ftp://example.com", "https://", "mailto:a@b.hu", "http://exa mple.com"])
    func invalidURL(text: String) async throws {
        let env = try ServiceTestEnvironment()
        await #expect(throws: ServiceError.invalidURL) {
            _ = try await env.productService().create(in: env.personal, draft: ProductDraft(name: "Milk", url: text))
        }
        #expect(try env.count(Product.self) == 0)
    }
}
