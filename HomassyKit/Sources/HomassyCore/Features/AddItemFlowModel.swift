import Foundation
import Observation

/// The stepwise add sheet: what (a product or a custom name), how much, and where from.
@MainActor
@Observable
public final class AddItemFlowModel {
    public enum Step: Int, Sendable, CaseIterable { case what, amount, store }

    public struct Suggestion: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
    }

    public private(set) var step: Step = .what
    public var query = "" {
        didSet { if query != oldValue { refreshSuggestions() } }
    }
    public private(set) var suggestions: [Suggestion] = []
    public private(set) var chosenName: String?
    public var quantityText: String
    public var unit: MeasureUnit = .piece
    public private(set) var errorMessage: String?
    private var selection = StoreSelection(preset: nil)

    @ObservationIgnored private let list: ShoppingList
    @ObservationIgnored private let shopping: ShoppingService
    @ObservationIgnored private let locations: ShoppingLocationService
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var product: Product?
    @ObservationIgnored private var suggestionProducts: [UUID: Product] = [:]

    public init(list: ShoppingList, shopping: ShoppingService, locations: ShoppingLocationService,
                locale: Locale = .current) {
        self.list = list
        self.shopping = shopping
        self.locations = locations
        self.locale = locale
        quantityText = Quantity.formatNumber(1, locale: locale)
    }

    public var space: Space? { list.space }
    public var units: [MeasureUnit] { MeasureUnit.allCases }
    public var storeName: String? { selection.name }
    public var suggestedDistance: Double? { selection.suggestedDistance }
    /// 1-based, for "1 of 3".
    public var stepNumber: Int { step.rawValue + 1 }

    public var quantity: Decimal? {
        guard let value = Quantity.parse(quantityText, locale: locale), value > 0 else { return nil }
        return value
    }

    public var canAdvance: Bool {
        switch step {
        case .what: chosenName != nil || query.nilIfBlank != nil
        case .amount: quantity != nil
        case .store: true
        }
    }

    public func unitLabel(_ unit: MeasureUnit) -> String { unit.name(for: quantity ?? 1, locale: locale) }

    public func chooseProduct(_ id: UUID) {
        guard let product = suggestionProducts[id] else { return }
        choose(product)
    }

    public func chooseCustom() {
        guard let name = query.nilIfBlank else { return }
        product = nil
        chosenName = name
        unit = .piece
        step = .amount
    }

    /// True when the barcode belongs to a product of the list's space, which is then chosen.
    public func chooseBarcode(_ code: String) -> Bool {
        guard let space, let barcode = code.nilIfBlank,
              let match = try? shopping.context.fetchEntities(
                Product.self, where: NSPredicate(format: "space == %@ AND barcode == %@", space, barcode)).first
        else { return false }
        choose(match)
        return true
    }

    public func setStore(_ location: ShoppingLocation?) { selection.choose(location) }

    public func applySuggestion(_ suggestion: StoreSuggestion) {
        guard let space else { return }
        selection.apply(suggestion, locations: locations, space: space)
    }

    public func next() {
        errorMessage = nil
        switch step {
        case .what:
            if chosenName != nil { step = .amount; return }
            let text = query.nilIfBlank
            if let text, let match = suggestionProducts.values.first(where: {
                $0.name.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                choose(match)
            } else {
                chooseCustom()
            }
        case .amount:
            guard quantity != nil else {
                errorMessage = coreLocalized("form.invalidQuantity")
                return
            }
            step = .store
        case .store:
            break
        }
    }

    public func back() {
        errorMessage = nil
        switch step {
        case .what: break
        case .amount:
            step = .what
            chosenName = nil
            product = nil
        case .store: step = .amount
        }
    }

    public func add() -> Bool {
        errorMessage = nil
        guard let quantity else {
            errorMessage = coreLocalized("form.invalidQuantity")
            return false
        }
        do {
            guard let space else { throw ServiceError.notFound }
            let store = try selection.resolve(locations: locations, space: space)
            try shopping.addItem(to: list, product: product, customName: product == nil ? chosenName : nil,
                                 quantity: quantity, unit: unit, shoppingLocation: store)
            return true
        } catch {
            errorMessage = FeatureError.message(for: error)
            return false
        }
    }

    private func choose(_ product: Product) {
        self.product = product
        chosenName = product.name
        unit = product.defaultUnit
        step = .amount
    }

    private func refreshSuggestions() {
        guard let space else { return }
        let products = (try? shopping.productSuggestions(matching: query, in: space)) ?? []
        suggestionProducts = Dictionary(products.map { ($0.publicId, $0) }, uniquingKeysWith: { first, _ in first })
        suggestions = products.map { Suggestion(id: $0.publicId, name: $0.name) }
    }
}
