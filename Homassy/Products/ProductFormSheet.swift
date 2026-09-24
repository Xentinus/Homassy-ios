import HomassyCore
import PhotosUI
import SwiftUI

struct ProductFormSheet: View {
    @State private var model: ProductFormModel
    @State private var pickerItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    private let onSaved: (Product) -> Void

    init(model: ProductFormModel, onSaved: @escaping (Product) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("product.form.photo") {
                    HStack(spacing: 16) {
                        ProductImageView(data: model.draft.imageData, size: 72)
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Label("product.form.choosePhoto", systemImage: "photo")
                            }
                            if model.draft.imageData != nil {
                                Button(role: .destructive) { model.setImage(nil) } label: {
                                    Label("product.form.removePhoto", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("product.field.name", text: $model.draft.name)
                        .accessibilityIdentifier("product.form.name")
                    if let error = model.nameError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    TextField("product.field.brand", text: $model.draft.brand)
                        .accessibilityIdentifier("product.form.brand")
                    TextField("product.field.category", text: $model.draft.category)
                        .accessibilityIdentifier("product.form.category")
                    let suggestions = model.suggestions()
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { model.draft.category = suggestion }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .accessibilityLabel(Text("product.form.suggestions"))
                    }
                    TextField("product.field.barcode", text: $model.draft.barcode)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("product.form.barcode")
                }
                Section {
                    Picker("product.field.unit", selection: $model.draft.defaultUnit) {
                        ForEach(MeasureUnit.allCases, id: \.self) { unit in
                            Text(unit.name(for: 1)).tag(unit)
                        }
                    }
                    Toggle("product.field.eatable", isOn: $model.draft.isEatable)
                    Toggle("product.field.favorite", isOn: $model.draft.isFavorite)
                }
                Section("product.field.notes") {
                    TextField("product.field.notes", text: $model.draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(model.isEditing ? "product.form.edit" : "product.form.new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task {
                            if let product = await model.save() {
                                onSaved(product)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("product.form.save")
                }
            }
            .onChange(of: pickerItem) {
                guard let item = pickerItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { model.setImage(data) }
                    pickerItem = nil
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.isSaving)
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    ProductFormSheet(model: ProductFormModel(mode: .create(model.personalSpace!, barcode: nil), service: model.services!.products))
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    ProductFormSheet(model: ProductFormModel(mode: .create(model.personalSpace!, barcode: nil), service: model.services!.products))
}
#endif
