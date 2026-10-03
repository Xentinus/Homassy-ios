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
        #expect(form.categoryText == "Dairy")
        form.draft.name = "Oat milk"
        #expect(await form.save() == milk)
        #expect(milk.name == "Oat milk")
    }

    @Test("Changes: any edit to the draft counts, undoing it does not")
    func hasChanges() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", category: "Dairy")
        let form = ProductFormModel(mode: .edit(milk), service: env.productService())
        #expect(!form.hasChanges)
        form.draft.name = "Milk 2"
        #expect(form.hasChanges)
        form.draft.name = "Milk"
        #expect(!form.hasChanges)
        form.setImage(Data([1, 2, 3]))
        #expect(form.hasChanges)

        let scanned = ProductFormModel(mode: .create(env.personal, barcode: "4000000000009", name: "Paprika"),
                                       service: env.productService())
        #expect(!scanned.hasChanges, "the seeded barcode and name are the starting point, not a change")
    }

    @Test("Category list: all, filtered by case and accents, the current one even before it is saved")
    func categoryList() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Milk", category: "Tejtermék")
        try await env.makeProduct("Bread", category: "Pékáru")
        let form = ProductFormModel(mode: .create(env.personal, barcode: nil), service: env.productService())
        #expect(form.categories(matching: "") == ["Pékáru", "Tejtermék"])
        #expect(form.categories(matching: "TEJ") == ["Tejtermék"])
        #expect(form.categories(matching: "pekaru") == ["Pékáru"])
        #expect(form.categories(matching: "  ") == ["Pékáru", "Tejtermék"])
        form.draft.category = "Italok"
        #expect(form.categories(matching: "") == ["Italok", "Pékáru", "Tejtermék"])
        #expect(form.categoryText == "Italok")
        form.draft.category = "   "
        #expect(form.categoryText == nil)
    }

    @Test("New category: only for text that names no existing category")
    func newCategory() async throws {
        let env = try ServiceTestEnvironment()
        try await env.makeProduct("Milk", category: "Tejtermék")
        let form = ProductFormModel(mode: .create(env.personal, barcode: nil), service: env.productService())
        #expect(form.newCategory(from: "") == nil)
        #expect(form.newCategory(from: "   ") == nil)
        #expect(form.newCategory(from: "tejtermek") == nil, "same name, different case and accents")
        #expect(form.newCategory(from: "  Tejes ital ") == "Tejes ital")
        #expect(form.newCategory(from: "Tej") == "Tej", "a prefix of an existing name is still new")
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
