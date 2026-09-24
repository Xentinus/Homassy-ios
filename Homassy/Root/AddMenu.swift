import SwiftUI

/// The toolbar `+` menu. Feature tasks keep it in their tab root's toolbar and supply the real items.
struct AddMenu<Items: View>: View {
    private let items: Items

    init(@ViewBuilder items: () -> Items) {
        self.items = items()
    }

    var body: some View {
        Menu {
            items
        } label: {
            Label("add.menu", systemImage: "plus")
        }
        .accessibilityIdentifier("addMenu")
    }
}
