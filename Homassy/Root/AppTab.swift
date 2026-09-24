import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case inventory, shopping, products, household, search

    var title: LocalizedStringKey {
        switch self {
        case .inventory: "tab.inventory"
        case .shopping: "tab.shopping"
        case .products: "tab.products"
        case .household: "tab.household"
        case .search: "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .inventory: "refrigerator"
        case .shopping: "cart"
        case .products: "shippingbox"
        case .household: "house"
        case .search: "magnifyingglass"
        }
    }
}
