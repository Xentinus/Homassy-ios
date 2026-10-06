import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case inventory, shopping, search

    var title: LocalizedStringKey {
        switch self {
        case .inventory: "tab.inventory"
        case .shopping: "tab.shopping"
        case .search: "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .inventory: "refrigerator"
        case .shopping: "cart"
        case .search: "magnifyingglass"
        }
    }
}
