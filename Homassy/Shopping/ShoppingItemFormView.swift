import HomassyCore
import SwiftUI

/// Edits one shopping list item: name (custom items), quantity, unit, deadline, store and note.
struct ShoppingItemFormView: View {
    let services: ServiceContainer
    let onSaved: () -> Void

    @State private var model: ShoppingItemFormModel
    @State private var pickingStore = false
    @Environment(\.dismiss) private var dismiss

    init(item: ShoppingListItem, services: ServiceContainer, onSaved: @escaping () -> Void) {
        self.services = services
        self.onSaved = onSaved
        _model = State(initialValue: ShoppingItemFormModel(service: services.shopping, item: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.hasProduct {
                        LabeledContent("shopping.form.product") { Text(verbatim: model.name) }
                    } else {
                        TextField("shopping.form.name", text: $model.name)
                            .accessibilityIdentifier("shopping.form.name")
                    }
                    TextField("shopping.form.quantity", text: $model.quantityText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("shopping.form.quantity")
                    Picker("shopping.form.unit", selection: $model.unit) {
                        ForEach(model.units, id: \.self) { unit in
                            Text(verbatim: model.unitLabel(unit)).tag(unit)
                        }
                    }
                }
                Section {
                    Toggle("shopping.form.hasDeadline", isOn: $model.hasDeadline.animation())
                        .accessibilityIdentifier("shopping.form.hasDeadline")
                    if model.hasDeadline {
                        DatePicker("shopping.form.deadline", selection: $model.deadline, displayedComponents: .date)
                    }
                    Button { pickingStore = true } label: {
                        LabeledContent("shopping.form.store") {
                            if let store = model.store {
                                Text(verbatim: store.name)
                            } else {
                                Text("shopping.form.store.none")
                            }
                        }
                    }
                    .accessibilityIdentifier("shopping.form.store")
                }
                Section {
                    TextField("shopping.form.note", text: $model.note, axis: .vertical)
                        .lineLimit(1...4)
                }
                if let error = model.errorMessage {
                    Section { Text(verbatim: error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text("shopping.form.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        if model.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("shopping.form.save")
                }
            }
            .sheet(isPresented: $pickingStore) {
                if let space = model.space {
                    StorePickerView(space: space, services: services) { model.setStore($0) }
                }
            }
        }
        .presentationDetents([.large])
    }
}
