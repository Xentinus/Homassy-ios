import HomassyCore
import SwiftUI

/// The add-stock details (P2-08a): unit, the lots, and the shared purchase date, store and paid total. Editing a
/// stock item uses the same page with one lot.
struct StockDetailsView: View {
    @Bindable var form: StockFormModel
    /// True when this page is the sheet's root (a known product, or editing).
    let showsCancel: Bool
    let onDone: () -> Void

    @Environment(ServiceContainer.self) private var services
    @State private var authorizer = CoreLocationAuthorizer()
    @State private var pickingStore = false

    var body: some View {
        Form {
            Section {
                Picker("stock.unit", selection: $form.unit) {
                    ForEach(MeasureUnit.allCases, id: \.self) { Text(verbatim: $0.name(for: 2)).tag($0) }
                }
                .accessibilityIdentifier("stock.unit")
            }
            StockLotsSection(lots: form.lots, unit: form.unit, purchasedAt: form.purchasedAt)
            Section {
                DatePicker("stock.purchase.date", selection: $form.purchasedAt, displayedComponents: .date)
                StoreMenu(model: form.store) { pickingStore = true }
                PriceFieldRow(price: $form.priceText, currency: $form.currency, priceIdentifier: "stock.price")
                if let error = form.priceError {
                    Text(verbatim: error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("stock.purchase")
            } footer: {
                if let split = form.priceSplitText { Text("stock.priceSplit \(split)") }
            }
            if let error = form.errorMessage {
                Section { Text(verbatim: error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(form.isEditing ? Text("stock.title.edit") : Text(verbatim: form.productName ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) { SheetCancelButton(action: onDone) }
            }
            ToolbarItem(placement: .confirmationAction) {
                SheetConfirmButton { if form.save() != nil { onDone() } }
                    .disabled(!form.canSave)
                    .accessibilityIdentifier("stock.save")
            }
        }
        .sheet(isPresented: $pickingStore) {
            if let space = form.targetSpace {
                StorePickerView(space: space, services: services) { form.store.setStore($0) }
            }
        }
        .task {
            guard !form.isEditing, let space = form.targetSpace,
                  let suggestion = await StoreSuggestionLoader.suggestion(for: space, services: services,
                                                                           authorizer: authorizer)
            else { return }
            form.store.applySuggestion(suggestion)
        }
    }
}
