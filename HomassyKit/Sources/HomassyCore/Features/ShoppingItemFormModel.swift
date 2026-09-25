import Foundation
import Observation

@MainActor
@Observable
public final class ShoppingItemFormModel {
    public struct StoreChoice: Equatable, Sendable {
        public let id: UUID
        public let name: String
    }

    public let hasProduct: Bool
    public var name: String
    public var quantityText: String
    public var unit: MeasureUnit
    public var note: String
    public var hasDeadline: Bool
    public var deadline: Date
    public private(set) var store: StoreChoice?
    public private(set) var errorMessage: String?

    @ObservationIgnored private let service: ShoppingService
    @ObservationIgnored private let item: ShoppingListItem
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var storeObject: ShoppingLocation?

    public var space: Space? { item.shoppingList?.space }
    public var units: [MeasureUnit] { MeasureUnit.allCases }

    public init(service: ShoppingService, item: ShoppingListItem, locale: Locale = .current, now: Date = .now) {
        self.service = service
        self.item = item
        self.locale = locale
        hasProduct = item.product != nil
        name = ShoppingService.displayName(of: item)
        quantityText = item.quantity.formatted(Decimal.FormatStyle(locale: locale).grouping(.never))
        unit = item.unit
        note = item.note ?? ""
        hasDeadline = item.deadline != nil
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        deadline = item.deadline ?? tomorrow
        storeObject = item.shoppingLocation
        store = item.shoppingLocation.map { StoreChoice(id: $0.publicId, name: $0.name) }
    }

    public func unitLabel(_ unit: MeasureUnit) -> String {
        unit.name(for: Quantity.parse(quantityText, locale: locale) ?? 1, locale: locale)
    }

    public func setStore(_ location: ShoppingLocation?) {
        storeObject = location
        store = location.map { StoreChoice(id: $0.publicId, name: $0.name) }
    }

    public func save() -> Bool {
        guard let quantity = Quantity.parse(quantityText, locale: locale), quantity > 0 else {
            errorMessage = ServiceError.quantityMustBePositive.errorDescription
            return false
        }
        do {
            try service.updateItem(item, product: item.product, customName: hasProduct ? nil : name,
                                   quantity: quantity, unit: unit, note: note,
                                   deadline: hasDeadline ? deadline : nil, shoppingLocation: storeObject)
            errorMessage = nil
            return true
        } catch {
            errorMessage = FeatureError.message(for: error)
            return false
        }
    }
}
