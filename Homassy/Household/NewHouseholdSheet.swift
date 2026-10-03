import HomassyCore
import SwiftUI

/// Creates a household (name + the user's own display name) and, once it exists, offers a first backup.
struct NewHouseholdSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceSelection.self) private var selection
    @State private var model: NewHouseholdModel
    @FocusState private var nameFocused: Bool

    init(service: SharingService) {
        _model = State(initialValue: NewHouseholdModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let space = model.createdSpace {
                    created(space)
                } else {
                    form
                }
            }
            .navigationTitle(Text("space.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.createdSpace == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCancelButton { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("household.new.create") { Task { await model.create() } }
                            .disabled(!model.canCreate)
                            .accessibilityIdentifier("household.new.create")
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetConfirmButton(title: "household.new.done") { finish() }
                            .accessibilityIdentifier("household.new.done")
                    }
                }
            }
            .interactiveDismissDisabled(model.isCreating)
            .onAppear { nameFocused = true }
        }
    }

    @ViewBuilder private var form: some View {
        @Bindable var model = model
        Section {
            TextField("household.new.name", text: $model.name)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { Task { await model.create() } }
                .accessibilityIdentifier("household.new.name")
            TextField("household.new.ownerName", text: $model.ownerDisplayName)
                .textContentType(.givenName)
                .accessibilityIdentifier("household.new.ownerName")
        } footer: {
            Text("household.sharing.ownerLoss")
        }
        if model.isCreating {
            Section { ProgressView().frame(maxWidth: .infinity) }
        }
        if let message = model.errorMessage {
            Section { Text(verbatim: message).foregroundStyle(.red) }
        }
    }

    @ViewBuilder private func created(_ space: Space) -> some View {
        Section {
            Label {
                Text("household.new.ready \(space.name)")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
            .accessibilityIdentifier("household.new.ready")
            Text("household.sharing.ownerLoss")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let message = model.errorMessage {
                Text(verbatim: message).font(.footnote).foregroundStyle(.red)
            }
        }
        Section {
            // Exported from inside the sheet: presenting the exporter after the sheet dismisses would get stuck.
            ArchiveExportButton(space: space) {
                Label("household.new.export", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("household.new.export")
        } footer: {
            Text("household.new.inviteHint")
        }
    }

    private func finish() {
        if let space = model.createdSpace { selection.select(space) }
        dismiss()
    }
}
