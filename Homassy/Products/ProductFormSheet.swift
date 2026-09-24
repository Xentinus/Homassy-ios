import HomassyCore
import PhotosUI
import SwiftUI

struct ProductFormSheet: View {
    @State private var model: ProductFormModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var takingPhoto = false
    /// A photo waiting in the editor (crop to a square, rotate); only the edited result reaches the draft.
    @State private var editing: EditablePhoto?

    struct EditablePhoto: Identifiable {
        let id = UUID()
        let data: Data
    }
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
                            if CameraPicker.isAvailable {
                                Button { takingPhoto = true } label: {
                                    Label("product.form.takePhoto", systemImage: "camera")
                                }
                                .accessibilityIdentifier("product.form.takePhoto")
                            }
                            choosePhotoButton
                            if let data = model.draft.imageData {
                                Button { editing = EditablePhoto(data: data) } label: {
                                    Label("product.form.editPhoto", systemImage: "crop.rotate")
                                }
                                .accessibilityIdentifier("product.form.editPhoto")
                                Button(role: .destructive) { model.setImage(nil) } label: {
                                    Label("product.form.removePhoto", systemImage: "trash")
                                }
                                .accessibilityIdentifier("product.form.removePhoto")
                            }
                        }
                        .buttonStyle(.borderless)
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
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { data in editing = EditablePhoto(data: data) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $editing) { photo in
                PhotoEditorView(data: photo.data) { model.setImage($0) }
            }
            .onChange(of: pickerItem) {
                guard let item = pickerItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { editing = EditablePhoto(data: data) }
                    pickerItem = nil
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.isSaving)
    }

    /// PhotosPicker, or under `-uiTestSamplePhoto` a button that hands the editor a generated photo
    /// (UI tests cannot drive the system photo picker).
    @ViewBuilder
    private var choosePhotoButton: some View {
        #if DEBUG
        if let sample = UITestHooks.samplePhoto {
            Button { editing = EditablePhoto(data: sample) } label: {
                Label("product.form.choosePhoto", systemImage: "photo")
            }
            .accessibilityIdentifier("product.form.choosePhoto")
        } else {
            photosPicker
        }
        #else
        photosPicker
        #endif
    }

    private var photosPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("product.form.choosePhoto", systemImage: "photo")
        }
        .accessibilityIdentifier("product.form.choosePhoto")
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
