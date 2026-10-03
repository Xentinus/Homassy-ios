import HomassyCore
import PhotosUI
import SwiftUI

/// New product and Edit product (P2-07b, mockup 1A · 2A · 3A · 4A · 5A): the Contacts "New Contact" pattern.
struct ProductFormSheet: View {
    @State private var model: ProductFormModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var choosingPhoto = false
    /// A photo waiting in the editor (crop to a square, rotate); only the edited result reaches the draft.
    @State private var editing: EditablePhoto?
    @State private var scanning = false
    @State private var confirmingDiscard = false
    @State private var didAutoFocus = false
    @FocusState private var focus: Field?

    /// A new product starts typing its name; the sheet must finish presenting before the field takes focus.
    private static let autoFocusDelay: Duration = .milliseconds(450)

    private enum Field: Hashable { case name, brand, barcode, website, notes }

    struct EditablePhoto: Identifiable {
        let id = UUID()
        let data: Data
    }
    @Environment(\.dismiss) private var dismiss
    private let onSaved: (Product) -> Void
    /// Editing only: the red "Delete product" at the bottom of the form (Apple's Contacts pattern, user
    /// decision 2026-09-25). The sheet closes first; the caller deletes with the undo toast.
    private let onDelete: (() -> Void)?

    init(model: ProductFormModel, onSaved: @escaping (Product) -> Void = { _ in }, onDelete: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProductFormPhotoHeader(
                        imageData: model.draft.imageData, name: model.draft.name,
                        takePhoto: CameraPicker.isAvailable ? { takingPhoto = true } : nil,
                        choosePhoto: choosePhoto,
                        editPhoto: { if let data = model.draft.imageData { editing = EditablePhoto(data: data) } },
                        removePhoto: { model.setImage(nil) })
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField("product.field.name", text: $model.draft.name)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .brand }
                        .accessibilityIdentifier("product.form.name")
                    if let error = model.nameError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    TextField("product.field.brand", text: $model.draft.brand)
                        .focused($focus, equals: .brand)
                        .submitLabel(.next)
                        .onSubmit { focus = .barcode }
                        .accessibilityIdentifier("product.form.brand")
                }
                Section {
                    NavigationLink {
                        ProductCategoryPicker(model: model)
                    } label: {
                        LabeledContent("product.field.category") {
                            if let category = model.categoryText { Text(verbatim: category) } else { Text("product.category.noneShort") }
                        }
                    }
                    .accessibilityIdentifier("product.form.category")
                    Picker("product.field.unit", selection: $model.draft.defaultUnit) {
                        ForEach(MeasureUnitGroup.allCases) { group in
                            Section(group.title) {
                                ForEach(group.units, id: \.self) { unit in Text(unit.name(for: 1)).tag(unit) }
                            }
                        }
                    }
                    .accessibilityIdentifier("product.form.unit")
                }
                Section {
                    HStack {
                        Image(systemName: "barcode").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("product.field.barcode", text: $model.draft.barcode)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .barcode)
                            .accessibilityIdentifier("product.form.barcode")
                        Button { scanning = true } label: {
                            Label("barcode.scan", systemImage: "barcode.viewfinder").labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("product.form.scan")
                    }
                    HStack {
                        Image(systemName: "link").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("product.field.website", text: $model.draft.url)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .website)
                            .accessibilityIdentifier("product.form.url")
                    }
                    if let error = model.urlError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    TextField("product.field.notes", text: $model.draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focus, equals: .notes)
                        .accessibilityIdentifier("product.form.notes")
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if model.isEditing, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            dismiss()
                            onDelete()
                        } label: {
                            Text("product.detail.deleteProduct").frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("product.form.delete")
                    }
                }
            }
            .navigationTitle(model.isEditing ? "product.form.edit" : "product.form.new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton(action: close)
                        .accessibilityIdentifier("product.form.cancel")
                        .confirmationDialog("product.form.discard.title", isPresented: $confirmingDiscard,
                                            titleVisibility: .visible) {
                            Button("product.form.discard.confirm", role: .destructive) { dismiss() }
                            Button("product.form.discard.keep", role: .cancel) {}
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton {
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
            .sheet(isPresented: $scanning) {
                BarcodeScannerSheet { code, _ in
                    model.draft.barcode = code
                    scanning = false
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
            .task {
                // Once per sheet: popping back from the category list must not pull the keyboard up again.
                guard !didAutoFocus, !model.isEditing, model.draft.name.isEmpty else { return }
                didAutoFocus = true
                try? await Task.sleep(for: Self.autoFocusDelay)
                focus = .name
            }
        }
        .presentationDetents([.large])
        // A changed form cannot be swiped away; ✕ asks first (Contacts, Calendar).
        .interactiveDismissDisabled(model.isSaving || model.hasChanges)
    }

    /// ✕: closes at once when nothing changed, otherwise asks before dropping the edits.
    private func close() {
        if model.hasChanges { confirmingDiscard = true } else { dismiss() }
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

private extension MeasureUnitGroup {
    var title: LocalizedStringKey {
        switch self {
        case .count: "unit.group.count"
        case .weight: "unit.group.weight"
        case .volume: "unit.group.volume"
        case .kitchen: "unit.group.kitchen"
        case .size: "unit.group.size"
        }
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
