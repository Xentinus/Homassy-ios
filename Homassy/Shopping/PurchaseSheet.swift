import HomassyCore
import SwiftUI

/// Tapping an item card: whether it goes into inventory (default on), how much was bought (with inventory, as
/// lots with their own storage location and expiry, P2-08a), whether the rest stays on the list, and from where
/// and for how much, which is recorded for the price trend. The store comes from the store menu (the nearest shop
/// is suggested) and the paid total is split across the lots.
struct PurchaseSheet: View {
    let services: ServiceContainer

    @State private var model: PurchaseFormModel
    @State private var authorizer = CoreLocationAuthorizer()
    @State private var pickingStore = false
    @Environment(UndoQueue.self) private var undoQueue
    @Environment(\.dismiss) private var dismiss

    init(item: ShoppingListItem, services: ServiceContainer) {
        self.services = services
        _model = State(initialValue: PurchaseFormModel(item: item, shopping: services.shopping,
                                                       inventory: services.inventory,
                                                       locations: services.shoppingLocations,
                                                       pending: services.pendingDeletions))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("shopping.purchase.addToInventory", isOn: $model.addToInventory.animation())
                        .accessibilityIdentifier("shopping.purchase.addToInventory")
                } footer: {
                    if !model.addToInventory {
                        if model.recordsPurchase {
                            Text("shopping.purchase.addToInventory.offRecorded")
                        } else {
                            Text("shopping.purchase.addToInventory.off")
                        }
                    }
                }
                if model.addToInventory {
                    StockLotsSection(lots: model.lots, unit: model.unit, purchasedAt: model.purchaseDate,
                                     listedText: model.listedText, header: "shopping.purchase.howMuch")
                    if model.showsKeepRemainder, let remainder = model.remainderText {
                        Section { keepToggle(remainder) }
                    }
                } else {
                    Section {
                        HStack {
                            TextField("shopping.purchase.quantity", text: $model.quantityText)
                                .keyboardType(.decimalPad)
                                .accessibilityIdentifier("shopping.purchase.quantity")
                            Text("shopping.purchase.of \(model.listedText)").foregroundStyle(.secondary)
                        }
                        if model.showsKeepRemainder, let remainder = model.remainderText { keepToggle(remainder) }
                    } header: {
                        Text("shopping.purchase.howMuch")
                    }
                }
                if model.recordsPurchase { purchaseSection }
                if let error = model.errorMessage {
                    Section { Text(verbatim: error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text(verbatim: model.itemName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("shopping.purchase.confirm", action: confirm)
                        .disabled(!model.canPurchase)
                        .accessibilityIdentifier("shopping.purchase.confirm")
                }
            }
            .sheet(isPresented: $pickingStore) {
                if let space = model.space {
                    StorePickerView(space: space, services: services) { model.setStore($0) }
                }
            }
            .task {
                guard let space = model.space,
                      let suggestion = await StoreSuggestionLoader.suggestion(for: space, services: services,
                                                                               authorizer: authorizer)
                else { return }
                model.applySuggestion(suggestion)
            }
        }
        .presentationDetents([.large])
    }

    private func keepToggle(_ remainder: String) -> some View {
        Toggle(isOn: $model.keepRemainder) { Text("shopping.purchase.keepRemainder \(remainder)") }
            .accessibilityIdentifier("shopping.purchase.keepRemainder")
    }

    /// Where and for how much: recorded for the price trend, with or without inventory (P4-05).
    private var purchaseSection: some View {
        Section {
            StoreMenu(model: model.store) { pickingStore = true }
            HStack {
                TextField("shopping.purchase.pricePaid", text: $model.priceText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("shopping.purchase.price")
                TextField("stock.currency", text: $model.currency)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 72)
            }
        } header: {
            Text("stock.purchase")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("shopping.purchase.price.footer")
                if let split = model.priceSplitText { Text("stock.priceSplit \(split)") }
            }
        }
    }

    private func confirm() {
        guard let action = model.purchase() else { return }
        undoQueue.enqueue(action)
        dismiss()
    }
}
