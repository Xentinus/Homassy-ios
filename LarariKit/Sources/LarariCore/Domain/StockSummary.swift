import Foundation

/// The stock line on a card: open items added up per unit ("12 db"), or "2 × 1 l" when every item of that
/// unit holds the same amount. Units follow `MeasureUnit`'s order and are joined with ", ".
enum StockSummary {
    @MainActor
    static func text(for items: [InventoryItem], locale: Locale) -> String? {
        text(for: items.filter { !$0.isFullyConsumed }.map { ($0.quantity, $0.unit) }, locale: locale)
    }

    static func text(for amounts: [(quantity: Decimal, unit: MeasureUnit)], locale: Locale) -> String? {
        let open = amounts.filter { $0.quantity > 0 }
        guard !open.isEmpty else { return nil }
        let byUnit = Dictionary(grouping: open, by: \.unit)
        let parts = MeasureUnit.allCases.compactMap { unit -> String? in
            guard let group = byUnit[unit] else { return nil }
            let quantities = group.map(\.quantity)
            if quantities.count > 1, Set(quantities).count == 1 {
                return "\(quantities.count) × \(Quantity.format(quantities[0], unit: unit, locale: locale))"
            }
            return Quantity.format(quantities.reduce(0, +), unit: unit, locale: locale)
        }
        return parts.joined(separator: ", ")
    }
}
