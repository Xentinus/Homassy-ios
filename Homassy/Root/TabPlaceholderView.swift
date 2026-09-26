import SwiftUI

/// Empty tab root with the tab's title, the space switcher and the `+` menu. Feature tasks replace it per tab.
struct TabPlaceholderView: View {
    let tab: AppTab

    var body: some View {
        ContentUnavailableView(emptyTitle, systemImage: tab.systemImage)
            .navigationTitle(tab.title)
            .toolbar {
                SpaceSwitcherToolbarItem()
                if let placeholder = addPlaceholder {
                    ToolbarItem(placement: .primaryAction) {
                        AddMenu {
                            // Placeholder: the feature task for this tab replaces it with the real action.
                            Button(placeholder.title, systemImage: placeholder.systemImage) {}
                                .disabled(true)
                        }
                    }
                }
            }
    }

    private var addPlaceholder: (title: LocalizedStringKey, systemImage: String)? {
        switch tab {
        case .inventory: ("add.inventoryItem", "plus.circle")
        case .shopping: ("add.shoppingList", "list.bullet")
        case .search: nil
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch tab {
        case .inventory: "empty.inventory"
        case .shopping: "empty.shopping"
        case .search: "empty.household"
        }
    }
}
