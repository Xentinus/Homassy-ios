import HomassyCore
import PhotosUI
import SwiftUI

/// The user's name, photo and colour in one household: offered on first visit and from the Members section.
struct MemberSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: MemberSetupModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var choosingPhoto = false
    /// A photo waiting in the square crop editor; only the edited result becomes the avatar.
    @State private var editing: EditablePhoto?
    private let userRecordName: String
    private let onSkip: (() -> Void)?

    struct EditablePhoto: Identifiable {
        let id = UUID()
        let data: Data
    }

    /// `onSkip` adds "Later" (first-visit setup); without it the sheet has Cancel.
    init(service: MemberService, space: Space, userRecordName: String, onSkip: (() -> Void)? = nil) {
        _model = State(initialValue: MemberSetupModel(service: service, space: space))
        self.userRecordName = userRecordName
        self.onSkip = onSkip
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    photoMenu
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("member.setup.name", text: $model.name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier("member.setup.name")
                } header: {
                    Text("member.setup.name")
                }
                Section {
                    colorPicker
                } header: {
                    Text("member.setup.color")
                } footer: {
                    Text("member.setup.footer \(model.spaceName)")
                }
                if let message = model.errorMessage {
                    Section { Text(verbatim: message).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text("member.setup.title \(model.spaceName)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if let onSkip {
                        Button("member.setup.later") { onSkip(); dismiss() }
                            .accessibilityIdentifier("member.setup.later")
                    } else {
                        Button("common.cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("member.setup.save")
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { data in editing = EditablePhoto(data: data) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $editing) { photo in
                PhotoEditorView(data: photo.data) { model.avatarData = $0 }
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
    }

    /// Every photo action in one menu behind the picture, like the product form.
    private var photoMenu: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button { takingPhoto = true } label: { Label("product.form.takePhoto", systemImage: "camera") }
            }
            Button { choosePhoto() } label: { Label("product.form.choosePhoto", systemImage: "photo.on.rectangle") }
                .accessibilityIdentifier("member.setup.choosePhoto")
            if model.avatarData != nil {
                Divider()
                Button(role: .destructive) { model.avatarData = nil } label: {
                    Label("product.form.removePhoto", systemImage: "trash")
                }
            }
        } label: {
            MemberAvatar(name: model.name, colorSeed: userRecordName, colorKey: model.colorKey,
                         avatar: model.avatarData, size: 96)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: model.avatarData == nil ? "camera.circle.fill" : "pencil.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Palette.mochaButtonForeground, Palette.mochaButtonBackground)
                        .offset(x: 4, y: 4)
                }
                .padding(8)
        }
        .accessibilityLabel(Text("member.setup.photo"))
        .accessibilityIdentifier("member.setup.photo")
    }

    /// Automatic, then the eight web colours and Mocha. The colour is shown as a dot, never as a fill.
    private var colorPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 12)], spacing: 12) {
            swatch(key: nil) {
                Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .overlay { Text(verbatim: "A").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            ForEach(MemberColor.selectablePresets, id: \.key) { preset in
                swatch(key: preset.key) { Circle().fill(Color.memberAccent(preset)) }
            }
            customSwatch
        }
        .padding(.vertical, 4)
    }

    private func swatch(key: String?, @ViewBuilder dot: () -> some View) -> some View {
        let selected = model.colorKey == key
        return Button { model.colorKey = key } label: {
            dot()
                .frame(width: 28, height: 28)
                .padding(3)
                .overlay { if selected { Circle().strokeBorder(Color.primary, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.colorName(key)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("member.color.\(key ?? "automatic")")
    }

    /// The system colour picker for any other colour, as the last swatch (like storage locations and lists).
    private var customSwatch: some View {
        let selected = MemberColor.isCustom(model.colorKey)
        let selection = Binding<Color>(
            get: { model.colorKey.flatMap(HexColor.parse).map(Color.init(hex:)) ?? Palette.mocha700 },
            set: { model.colorKey = HexColor.format($0.rgbHex) })
        return ZStack {
            ColorPicker(selection: selection, supportsOpacity: false) {
                Text("member.color.custom")
            }
            .labelsHidden()
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("member.color.custom")
            if selected {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: 2)
                    .frame(width: 34, height: 34)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 34, minHeight: 34)
    }

    static func colorName(_ key: String?) -> LocalizedStringKey {
        switch key {
        case nil: "member.color.automatic"
        case "rose": "member.color.rose"
        case "amber": "member.color.amber"
        case "lime": "member.color.lime"
        case "teal": "member.color.teal"
        case "sky": "member.color.sky"
        case "indigo": "member.color.indigo"
        case "violet": "member.color.violet"
        case "fuchsia": "member.color.fuchsia"
        default: "member.color.mocha"
        }
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

    private func save() {
        guard model.canSave else { return }
        model.save()
        if model.didSave { dismiss() }
    }
}
