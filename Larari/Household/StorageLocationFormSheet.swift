import LarariCore
import SwiftUI

struct StorageLocationFormSheet: View {
    @State private var model: StorageLocationFormModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(model: StorageLocationFormModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("storageLocations.form.name", text: $model.name)
                        .accessibilityIdentifier("storageLocation.name")
                }
                Section("storageLocations.form.color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        swatch(nil)
                        ForEach(StorageColor.palette) { swatch($0) }
                        customSwatch
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Toggle("storageLocations.form.freezer", isOn: $model.isFreezer)
                        .accessibilityIdentifier("storageLocation.freezer")
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(model.isEditing ? "storageLocations.edit" : "storageLocations.new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCancelButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton { if model.save() { dismiss() } }
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("storageLocation.save")
                }
            }
        }
        .presentationDetents(verticalSizeClass == .compact ? [.large] : [.medium, .large])
    }

    /// The system colour picker for any other colour, shown as the last swatch.
    private var customSwatch: some View {
        let selected = model.color?.isCustom == true
        let selection = Binding<Color>(
            get: { model.color.flatMap { $0.isCustom ? $0.color : nil } ?? Palette.mocha700 },
            set: { model.color = StorageColor.custom(from: $0) })
        return ZStack {
            ColorPicker(selection: selection, supportsOpacity: false) {
                Text(StorageColor.custom(0).localizedName)
            }
            .labelsHidden()
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("color.custom")
            if selected {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private func swatch(_ color: StorageColor?) -> some View {
        let selected = model.color == color
        return Button { model.color = color } label: {
            ZStack {
                Circle()
                    .fill(color?.color ?? Color.clear)
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: color == nil ? 1 : 0))
                if color == nil {
                    Image(systemName: "slash.circle").foregroundStyle(.secondary)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.bold())
                        .foregroundStyle(color == nil ? Color.primary : Color.white)
                }
            }
            .frame(width: 36, height: 36)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.map { Text($0.localizedName) } ?? Text("storageLocations.form.noColor"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("color.\(color?.rawValue ?? "none")")
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    StorageLocationFormSheet(model: StorageLocationFormModel(mode: .create(model.personalSpace!),
                                                             service: model.services!.storageLocations))
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    StorageLocationFormSheet(model: StorageLocationFormModel(mode: .create(model.personalSpace!),
                                                             service: model.services!.storageLocations))
}
#endif
