import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("ProductFormModel")
struct ProductFormModelTests {
    @Test func createWithPrefilledBarcode() async throws {
        let env = try ServiceTestEnvironment()
        let form = ProductFormModel(mode: .create(env.personal, barcode: "4000000000009"), service: env.productService())
        #expect(form.draft.barcode == "4000000000009")
        #expect(!form.isEditing && !form.canSave)
        form.draft.name = "Paprika"
        form.draft.defaultUnit = .gram
        #expect(form.canSave)
        let product = try #require(await form.save())
        #expect(product.name == "Paprika" && product.barcode == "4000000000009" && product.defaultUnit == .gram)
        #expect(form.nameError == nil && form.errorMessage == nil && !form.isSaving)
    }

    @Test func blankNameShowsInlineError() async throws {
        let env = try ServiceTestEnvironment()
        let form = ProductFormModel(mode: .create(env.personal, barcode: nil), service: env.productService())
        form.draft.name = "   "
        #expect(await form.save() == nil)
        #expect(form.nameError == ServiceError.nameRequired.errorDescription)
        #expect(form.errorMessage == nil)
        form.draft.name = "Salt"
        #expect(await form.save() != nil)
        #expect(form.nameError == nil)
    }

    @Test func unreadableImageShowsGeneralError() async throws {
        let env = try ServiceTestEnvironment()
        let form = ProductFormModel(mode: .create(env.personal, barcode: nil), service: env.productService())
        form.draft.name = "Salt"
        form.setImage(Data("not an image".utf8))
        #expect(await form.save() == nil)
        #expect(form.errorMessage == ImageProcessor.Failure.undecodable.errorDescription)
        form.setImage(nil)
        #expect(await form.save() != nil)
    }

    @Test func editLoadsAndSaves() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", category: "Dairy")
        try await env.makeProduct("Bread", category: "Bakery")
        let form = ProductFormModel(mode: .edit(milk), service: env.productService())
        #expect(form.isEditing && form.draft.name == "Milk" && form.draft.category == "Dairy")
        #expect(form.categorySuggestions == ["Bakery", "Dairy"])
        form.draft.category = "ba"
        #expect(form.suggestions() == ["Bakery"])
        form.draft.category = "Bakery"
        #expect(form.suggestions().isEmpty)
        form.draft.category = ""
        #expect(form.suggestions() == ["Bakery", "Dairy"])
        form.draft.name = "Oat milk"
        #expect(await form.save() == milk)
        #expect(milk.name == "Oat milk")
    }

    @Test func readOnlyShowsError() async throws {
        let env = try ServiceTestEnvironment()
        let form = ProductFormModel(mode: .create(env.personal, barcode: nil), service: env.productService(canEdit: { _ in false }))
        form.draft.name = "Salt"
        #expect(await form.save() == nil)
        #expect(form.errorMessage == ServiceError.readOnlySpace.errorDescription)
    }
}

@MainActor
@Suite("ProductFormModel link")
struct ProductFormLinkTests {
    @Test func invalidLinkShowsInlineError() async throws {
        let env = try ServiceTestEnvironment()
        let form = ProductFormModel(mode: .create(env.personal, barcode: nil), service: env.productService())
        form.draft.name = "Milk"
        form.draft.url = "not a link"
        #expect(await form.save() == nil)
        #expect(form.urlError == ServiceError.invalidURL.errorDescription)
        #expect(form.nameError == nil && form.errorMessage == nil)
        form.draft.url = "mizo.hu"
        let product = try #require(await form.save())
        #expect(product.url == "https://mizo.hu")
        #expect(form.urlError == nil)
    }

    @Test func editLoadsTheLink() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.productService().create(in: env.personal, draft: ProductDraft(name: "Milk", url: "https://mizo.hu"))
        let form = ProductFormModel(mode: .edit(milk), service: env.productService())
        #expect(form.draft.url == "https://mizo.hu")
    }
}
