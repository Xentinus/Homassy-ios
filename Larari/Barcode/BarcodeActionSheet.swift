import SwiftUI

struct BarcodeActionSheet: View {
    let productName: String
    let canEdit: Bool
    /// False when the household has no shopping list yet; the button then stays off and the footer says why.
    let hasShoppingLists: Bool
    let onAddToInventory: () -> Void
    let onAddToList: () -> Void
    let onCheckStock: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(productName).font(.title3.weight(.semibold))
                } header: {
                    Text("barcode.found")
                }
                Section {
                    Button { onAddToInventory() } label: {
                        Label("barcode.addToInventory", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(!canEdit)
                    .accessibilityIdentifier("barcode.addToInventory")
                    Button { onAddToList() } label: {
                        Label("barcode.addToList", systemImage: "cart.badge.plus")
                    }
                    .disabled(!canEdit || !hasShoppingLists)
                    .accessibilityIdentifier("barcode.addToList")
                    Button { onCheckStock() } label: {
                        Label("barcode.checkStock", systemImage: "shippingbox")
                    }
                    .accessibilityIdentifier("barcode.checkStock")
                } footer: {
                    if canEdit && !hasShoppingLists {
                        Text("barcode.addToList.noLists")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCancelButton(title: "common.close", role: .close) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
