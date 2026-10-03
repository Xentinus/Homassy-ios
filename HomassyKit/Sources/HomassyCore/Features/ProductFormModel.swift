import Foundation
import Observation

@MainActor
@Observable
public final class ProductFormModel {
    public enum Mode {
        case create(Space, barcode: String?, name: String? = nil)
        case edit(Product)
    }

    public var draft: ProductDraft
    public private(set) var nameError: String?
    public private(set) var urlError: String?
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    public private(set) var categorySuggestions: [String] = []

    private let mode: Mode
    private let service: ProductService
    private let initialDraft: ProductDraft

    public init(mode: Mode, service: ProductService) {
        self.mode = mode
        self.service = service
        let space: Space?
        let start: ProductDraft
        switch mode {
        case .create(let target, let barcode, let name):
            start = ProductDraft(name: name ?? "", barcode: barcode ?? "")
            space = target
        case .edit(let product):
            start = ProductDraft(product: product)
            space = product.space
        }
        draft = start
        initialDraft = start
        categorySuggestions = space.flatMap { try? service.categories(in: $0) } ?? []
    }

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var canSave: Bool { draft.name.nilIfBlank != nil && !isSaving }

    public func setImage(_ data: Data?) { draft.imageData = data }

    /// Whether closing the form would lose anything (the discard confirmation, P2-07b).
    public var hasChanges: Bool { draft != initialDraft }

    /// The trimmed category, or nil when the field is blank ("Nincs" on the form row).
    public var categoryText: String? { draft.category.nilIfBlank }

    /// The category picker's rows (2A): the space's categories plus the draft's own, filtered by `query`
    /// ignoring case and accents. A blank query lists them all.
    public func categories(matching query: String) -> [String] {
        let all = knownCategories
        guard let typed = query.nilIfBlank else { return all }
        return all.filter { $0.range(of: typed, options: Self.matching) != nil }
    }

    /// The search text as a new category ("„x” új kategóriaként"), unless it is blank or already a category.
    public func newCategory(from query: String) -> String? {
        guard let typed = query.nilIfBlank else { return nil }
        return knownCategories.contains { $0.compare(typed, options: Self.matching) == .orderedSame } ? nil : typed
    }

    private static let matching: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// A category picked as new is listed (and ticked) before the product is saved.
    private var knownCategories: [String] {
        guard let current = categoryText,
              !categorySuggestions.contains(where: { $0.compare(current, options: Self.matching) == .orderedSame })
        else { return categorySuggestions }
        return [current] + categorySuggestions
    }

    public func save() async -> Product? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        nameError = nil
        urlError = nil
        errorMessage = nil
        do {
            switch mode {
            case .create(let space, _, _):
                return try await service.create(in: space, draft: draft)
            case .edit(let product):
                try await service.update(product, with: draft)
                return product
            }
        } catch ServiceError.nameRequired {
            nameError = ServiceError.nameRequired.errorDescription
        } catch ServiceError.invalidURL {
            urlError = ServiceError.invalidURL.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }
}
