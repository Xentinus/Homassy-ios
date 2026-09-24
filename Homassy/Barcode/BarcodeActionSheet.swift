import SwiftUI

struct BarcodeActionSheet: View {
    let productName: String
    let canEdit: Bool
    let onAddToInventory: () -> Void
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
                    Button {} label: {
                        Label("barcode.addToList", systemImage: "cart.badge.plus")
                    }
                    .disabled(true)
                    .accessibilityIdentifier("barcode.addToList")
                    Button { onCheckStock() } label: {
                        Label("barcode.checkStock", systemImage: "shippingbox")
                    }
                    .accessibilityIdentifier("barcode.checkStock")
                } footer: {
                    Text("barcode.addToList.later")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
