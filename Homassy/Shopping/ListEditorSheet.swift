import HomassyCore
import SwiftUI

/// Creates or edits a list: its name and tag colour.
struct ListEditorSheet: View {
    enum Mode: Identifiable, Hashable {
        case create
        case edit(UUID)
        var id: String {
            switch self {
            case .create: "create"
            case .edit(let id): id.uuidString
            }
        }
    }

    let mode: Mode
    let model: ShoppingListsModel
    @State private var name: String
    @State private var color: String?
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, model: ShoppingListsModel) {
        self.mode = mode
        self.model = model
        if case .edit(let id) = mode, let summary = model.summaries.first(where: { $0.id == id }) {
            _name = State(initialValue: summary.name)
            _color = State(initialValue: summary.color)
        } else {
            _name = State(initialValue: "")
            _color = State(initialValue: ShoppingListPalette.colors.first)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("shopping.listEditor.name", text: $name)
                    .accessibilityIdentifier("shopping.listEditor.name")
                    .submitLabel(.done)
                    .onSubmit(save)
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(Array(ShoppingListPalette.colors.enumerated()), id: \.element) { index, hex in
                            Button { color = hex } label: {
                                Circle()
                                    .fill(ListColor.color(hex))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if color == hex {
                                            Circle().strokeBorder(.primary, lineWidth: 3).padding(-4)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("shopping.listEditor.colorOption \(index + 1)"))
                            .accessibilityAddTraits(color == hex ? .isSelected : [])
                        }
                        customSwatch
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("shopping.listEditor.color")
                }
            }
            .navigationTitle(Text(mode == .create ? LocalizedStringKey("shopping.lists.new")
                                                  : LocalizedStringKey("shopping.listEditor.editTitle")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("shopping.listEditor.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Any other colour from the system colour picker, stored as `#rrggbb` (the same pattern as storage locations).
    private var customSwatch: some View {
        let selected = ShoppingListPalette.isCustom(color)
        let selection = Binding<Color>(
            get: { selected ? ListColor.color(color) : Palette.mocha700 },
            set: { color = ListColor.hex(from: $0) })
        return ZStack {
            ColorPicker(selection: selection, supportsOpacity: false) {
                Text("shopping.listEditor.custom")
            }
            .labelsHidden()
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("color.custom")
            if selected {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: 3)
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 44, height: 44)
    }

    private func save() {
        let saved: Bool
        switch mode {
        case .create: saved = model.createList(name: name, color: color)
        case .edit(let id): saved = model.updateList(id, name: name, color: color)
        }
        if saved { dismiss() }
    }
}
