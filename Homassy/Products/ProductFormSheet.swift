import HomassyCore
import PhotosUI
import SwiftUI

struct ProductFormSheet: View {
    @State private var model: ProductFormModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var choosingPhoto = false
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
                Section {
                    photoMenu
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
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
                    TextField("product.field.url", text: $model.draft.url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("product.form.url")
                    if let error = model.urlError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    Picker("product.field.unit", selection: $model.draft.defaultUnit) {
                        ForEach(MeasureUnit.allCases, id: \.self) { unit in
                            Text(unit.name(for: 1)).tag(unit)
                        }
                    }
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
            .photosPicker(isPresented: $choosingPhoto, selection: $pickerItem, matching: .images)
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

    /// The photo, with every photo action in one menu behind it (user request, 2026-09-24).
    private var photoMenu: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button { takingPhoto = true } label: { Label("product.form.takePhoto", systemImage: "camera") }
                    .accessibilityIdentifier("product.form.takePhoto")
            }
            Button { choosePhoto() } label: { Label("product.form.choosePhoto", systemImage: "photo.on.rectangle") }
                .accessibilityIdentifier("product.form.choosePhoto")
            if let data = model.draft.imageData {
                Button { editing = EditablePhoto(data: data) } label: { Label("product.form.editPhoto", systemImage: "crop.rotate") }
                    .accessibilityIdentifier("product.form.editPhoto")
                Divider()
                Button(role: .destructive) { model.setImage(nil) } label: { Label("product.form.removePhoto", systemImage: "trash") }
                    .accessibilityIdentifier("product.form.removePhoto")
            }
        } label: {
            ProductImageView(data: model.draft.imageData, size: 120)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: model.draft.imageData == nil ? "camera.circle.fill" : "pencil.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Palette.mochaButtonForeground, Palette.mochaButtonBackground)
                        .offset(x: 8, y: 8)
                }
                .padding(8)
        }
        .accessibilityLabel(Text(model.draft.imageData == nil ? "product.form.addPhoto" : "product.form.photo"))
        .accessibilityIdentifier("product.form.photo")
    }

    /// The system photo picker, or under `-uiTestSamplePhoto` a generated picture (UI tests cannot drive the picker).
    private func choosePhoto() {
        #if DEBUG
        if let sample = UITestHooks.samplePhoto {
            editing = EditablePhoto(data: sample)
            return
        }
        #endif
        choosingPhoto = true
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
