import Foundation
import Observation

@MainActor
@Observable
public final class ProductFormModel {
    public enum Mode {
        case create(Space, barcode: String?)
        case edit(Product)
    }

    public var draft: ProductDraft
    public private(set) var nameError: String?
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    public private(set) var categorySuggestions: [String] = []

    private let mode: Mode
    private let service: ProductService

    public init(mode: Mode, service: ProductService) {
        self.mode = mode
        self.service = service
        let space: Space?
        switch mode {
        case .create(let target, let barcode):
            draft = ProductDraft(barcode: barcode ?? "")
            space = target
        case .edit(let product):
            draft = ProductDraft(product: product)
            space = product.space
        }
        categorySuggestions = space.flatMap { try? service.categories(in: $0) } ?? []
    }

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var canSave: Bool { draft.name.nilIfBlank != nil && !isSaving }

    public func setImage(_ data: Data?) { draft.imageData = data }

    /// Existing categories that start with or contain the typed text; all of them while the field is empty.
    public func suggestions() -> [String] {
        guard let typed = draft.category.nilIfBlank else { return categorySuggestions }
        return categorySuggestions.filter {
            $0.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                && $0.caseInsensitiveCompare(typed) != .orderedSame
        }
    }

    public func save() async -> Product? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        nameError = nil
        errorMessage = nil
        do {
            switch mode {
            case .create(let space, _):
                return try await service.create(in: space, draft: draft)
            case .edit(let product):
                try await service.update(product, with: draft)
                return product
            }
        } catch ServiceError.nameRequired {
            nameError = ServiceError.nameRequired.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }
}
