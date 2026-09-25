import HomassyCore
import SwiftUI

/// Tapping an item card: how much was bought, whether the rest stays on the list, from where (the nearest
/// shop is suggested) and for how much, which is recorded for the price trend, and whether it goes into
/// inventory (default on) with expiry and storage location.
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
                    HStack {
                        TextField("shopping.purchase.quantity", text: $model.quantityText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("shopping.purchase.quantity")
                        Text("shopping.purchase.of \(model.listedText)").foregroundStyle(.secondary)
                    }
                    if model.showsKeepRemainder, let remainder = model.remainderText {
                        Toggle(isOn: $model.keepRemainder) { Text("shopping.purchase.keepRemainder \(remainder)") }
                            .accessibilityIdentifier("shopping.purchase.keepRemainder")
                    }
                } header: {
                    Text("shopping.purchase.howMuch")
                }
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
                if model.recordsPurchase { purchaseSections }
                if model.addToInventory { inventorySection }
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

    /// Where and for how much: recorded for the price trend, with or without inventory (P4-05).
    @ViewBuilder private var purchaseSections: some View {
        Section {
            StoreSuggestionRow(name: model.storeName, distance: model.suggestedDistance) { pickingStore = true }
        } header: {
            Text("shopping.purchase.fromWhere")
        }
        Section {
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
            Text("shopping.purchase.price")
        } footer: {
            Text("shopping.purchase.price.footer")
        }
    }

    private var inventorySection: some View {
        Section {
            Toggle("stock.hasExpiry", isOn: $model.hasExpiry.animation())
            if model.hasExpiry {
                DatePicker("stock.expiresAt", selection: $model.expiresAt, displayedComponents: .date)
            }
            Picker("stock.location", selection: $model.storageLocationID) {
                Text("inventory.noLocation").tag(UUID?.none)
                ForEach(model.storageOptions) { Text(verbatim: $0.name).tag(Optional($0.id)) }
            }
        } header: {
            Text("shopping.purchase.toInventory")
        }
    }

    private func confirm() {
        guard let action = model.purchase() else { return }
        undoQueue.enqueue(action)
        dismiss()
    }
}
