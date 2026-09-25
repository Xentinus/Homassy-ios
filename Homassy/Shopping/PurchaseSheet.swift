import HomassyCore
import SwiftUI

/// Tapping an item card: how much was bought, from where (the nearest shop is suggested), whether the
/// rest stays on the list, and the optional price, expiry and storage location. Goes straight to inventory.
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
                    StoreSuggestionRow(name: model.storeName, distance: model.suggestedDistance) { pickingStore = true }
                } header: {
                    Text("shopping.purchase.fromWhere")
                }
                Section {
                    HStack {
                        TextField("stock.price", text: $model.priceText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("shopping.purchase.price")
                        TextField("stock.currency", text: $model.currency)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 72)
                    }
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

    private func confirm() {
        guard let action = model.purchase() else { return }
        undoQueue.enqueue(action)
        dismiss()
    }
}
