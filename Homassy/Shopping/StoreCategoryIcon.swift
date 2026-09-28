import MapKit
import SwiftUI

/// A place's Apple Maps category as a coloured circle with a white glyph (P2-08c, like Apple Maps), so a shop,
/// a post office and a pharmacy look different in the store picker. Unknown categories get a gray pin.
struct StoreCategoryIcon: View {
    let category: String?

    var body: some View {
        let style = Self.style(for: category)
        Image(systemName: style.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(style.color))
            .accessibilityHidden(true)   // the category name is read in the row text
    }

    /// The localized category name, or nil for an unknown or missing category.
    static func name(for category: String?) -> LocalizedStringKey? {
        style(for: category).key.map { LocalizedStringKey($0) }
    }

    /// The category name first, then the rest: "Hipermarket · Sport u. 2–4., Budaörs".
    static func subtitle(category: String?, _ rest: String?) -> String? {
        let name = style(for: category).key.map { String(localized: String.LocalizationValue($0)) }
        let parts = [name, rest].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private struct Style {
        let symbol: String
        let color: Color
        let key: String?
    }

    private static func style(for category: String?) -> Style {
        switch category.map(MKPointOfInterestCategory.init(rawValue:)) {
        case .foodMarket: Style(symbol: "cart.fill", color: .green, key: "store.category.foodMarket")
        case .store: Style(symbol: "bag.fill", color: .yellow, key: "store.category.store")
        case .bakery: Style(symbol: "birthday.cake.fill", color: .orange, key: "store.category.bakery")
        case .pharmacy: Style(symbol: "cross.case.fill", color: .red, key: "store.category.pharmacy")
        case .postOffice: Style(symbol: "envelope.fill", color: .blue, key: "store.category.postOffice")
        case .restaurant: Style(symbol: "fork.knife", color: .orange, key: "store.category.restaurant")
        case .cafe: Style(symbol: "cup.and.saucer.fill", color: .brown, key: "store.category.cafe")
        case .gasStation: Style(symbol: "fuelpump.fill", color: .blue, key: "store.category.gasStation")
        case .bank: Style(symbol: "building.columns.fill", color: .indigo, key: "store.category.bank")
        case .atm: Style(symbol: "banknote.fill", color: .green, key: "store.category.atm")
        case .hospital: Style(symbol: "cross.fill", color: .red, key: "store.category.hospital")
        case .laundry: Style(symbol: "washer.fill", color: .teal, key: "store.category.laundry")
        case .fitnessCenter: Style(symbol: "figure.run", color: .orange, key: "store.category.fitnessCenter")
        default: Style(symbol: "mappin", color: .gray, key: nil)
        }
    }
}
