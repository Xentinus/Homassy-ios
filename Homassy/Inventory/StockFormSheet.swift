import HomassyCore
import SwiftUI

/// Add stock (pick or create a product, amount, unit, dates, location, price) or edit a stock item.
struct StockFormSheet: View {
    @State private var model: StockFormModel
    @State private var creatingProduct = false
    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    init(model: StockFormModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("stock.product", selection: $model.productID) {
                        Text("stock.product.choose").tag(UUID?.none)
                        ForEach(model.productOptions) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .disabled(model.isEditing)
                    .accessibilityIdentifier("stock.product")
                    if !model.isEditing {
                        Button { creatingProduct = true } label: { Label("add.product", systemImage: "plus") }
                            .accessibilityIdentifier("stock.newProduct")
                    }
                }
                Section {
                    HStack {
                        TextField("stock.quantity", text: $model.quantityText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("stock.quantity")
                        Picker("stock.unit", selection: $model.unit) {
                            ForEach(MeasureUnit.allCases, id: \.self) { Text($0.shortLabel(for: 2)).tag($0) }
                        }
                        .labelsHidden()
                    }
                    if let error = model.quantityError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    Toggle("stock.hasExpiry", isOn: $model.hasExpiry)
                    if model.hasExpiry {
                        DatePicker("stock.expiresAt", selection: $model.expiresAt, displayedComponents: .date)
                    }
                    DatePicker("stock.purchasedAt", selection: $model.purchasedAt, displayedComponents: .date)
                }
                Section {
                    Picker("stock.location", selection: $model.locationID) {
                        Text("inventory.noLocation").tag(UUID?.none)
                        ForEach(model.locationOptions) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section {
                    HStack {
                        TextField("stock.price", text: $model.priceText)
                            .keyboardType(.decimalPad)
                        TextField("stock.currency", text: $model.currency)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 72)
                    }
                    if let error = model.priceError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(model.isEditing ? "stock.title.edit" : "stock.title.add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { if model.save() != nil { dismiss() } }
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("stock.save")
                }
            }
            .sheet(isPresented: $creatingProduct) {
                if let space = model.targetSpace {
                    ProductFormSheet(model: ProductFormModel(mode: .create(space, barcode: nil), service: services.products)) {
                        model.productCreated($0)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    let services = model.services!
    StockFormSheet(model: StockFormModel(mode: .add(model.personalSpace!, productID: nil), inventory: services.inventory,
                                         products: services.products, storage: services.storageLocations))
        .environment(services)
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    let services = model.services!
    StockFormSheet(model: StockFormModel(mode: .add(model.personalSpace!, productID: nil), inventory: services.inventory,
                                         products: services.products, storage: services.storageLocations))
        .environment(services)
}
#endif
