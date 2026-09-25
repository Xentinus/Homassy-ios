import HomassyCore
import SwiftUI

/// The import sheet: file details, per-collection counts, and the choice between a new household and a merge.
/// Nothing is written until Import is tapped.
struct ImportFlowView: View {
    let url: URL
    let onFinished: (Space) -> Void

    @State private var model: ArchiveImportModel
    @Environment(\.dismiss) private var dismiss

    init(url: URL, archive: ArchiveServices, undoQueue: UndoQueue, onFinished: @escaping (Space) -> Void) {
        self.url = url
        self.onFinished = onFinished
        _model = State(initialValue: ArchiveImportModel(importer: archive.makeImporter(), spaceStore: archive.spaceStore,
                                                        prepare: { try undoQueue.commitAll() }))
    }

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(Text("archive.import.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.phase == .importing)
        .presentationDetents([.large])
        .task { if model.phase == .idle { model.load(url: url) } }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if model.phase == .finished {
            ToolbarItem(placement: .confirmationAction) {
                Button("archive.import.done.button") { dismiss() }
                    .accessibilityIdentifier("import.close")
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("archive.import.cancel") { dismiss() }
                    .accessibilityIdentifier("import.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("archive.import.confirm") {
                    if let space = model.confirm() { onFinished(space) }
                }
                .disabled(!model.canConfirm)
                .accessibilityIdentifier("import.confirm")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            Section { ProgressView { Text("archive.import.loading") } }
        case .failed(let message):
            Section {
                ContentUnavailableView {
                    Label("archive.import.failed.title", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(verbatim: message)
                }
            }
        case .finished:
            Section {
                Label {
                    Text("archive.import.done.title \(model.importedSpace?.name ?? "")")
                        .accessibilityIdentifier("import.done")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
        case .ready, .importing:
            if let preview = model.preview { readyContent(preview) }
        }
    }

    @ViewBuilder private func readyContent(_ preview: ImportPreview) -> some View {
        Section {
            LabeledContent("archive.import.source") { Text(verbatim: preview.manifest.spaceName) }
            LabeledContent("archive.import.exportedAt") {
                Text(preview.manifest.exportedAt, format: .dateTime.year().month().day().hour().minute())
            }
            LabeledContent("archive.import.appVersion") { Text(verbatim: preview.manifest.appVersion) }
        }

        Section {
            ForEach(ArchiveEntity.allCases, id: \.self) { entity in
                let counts = preview.counts(for: entity)
                LabeledContent {
                    Text(counts.total, format: .number)
                        .accessibilityIdentifier("import.count.\(entity.rawValue)")
                } label: {
                    Text(Self.title(for: entity))
                    if preview.isMerge {
                        Text("archive.import.breakdown \(counts.toCreate) \(counts.toUpdate) \(counts.unchanged)")
                    }
                }
            }
        } header: {
            Text("archive.import.contents")
        }

        Section {
            Picker(selection: $model.choice) {
                Text("archive.import.mode.newSpace").tag(ArchiveImportModel.Choice.newSpace)
                ForEach(model.targets) { target in
                    Text("archive.import.mode.merge \(target.name)").tag(ArchiveImportModel.Choice.merge(target.id))
                }
            } label: {
                Text("archive.import.mode")
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(model.phase == .importing)

            if model.choice == .newSpace {
                TextField("archive.import.newSpaceName", text: $model.newSpaceName)
                    .accessibilityIdentifier("import.newSpaceName")
            }
        } header: {
            Text("archive.import.mode")
        } footer: {
            Text(model.choice == .newSpace ? LocalizedStringKey("archive.import.newSpace.footer")
                                           : LocalizedStringKey("archive.import.merge.footer"))
        }

        if model.phase == .importing {
            Section { ProgressView() }
        }
    }

    static func title(for entity: ArchiveEntity) -> LocalizedStringKey {
        switch entity {
        case .members: "archive.entity.members"
        case .products: "archive.entity.products"
        case .storageLocations: "archive.entity.storageLocations"
        case .shoppingLocations: "archive.entity.shoppingLocations"
        case .shoppingLists: "archive.entity.shoppingLists"
        case .inventoryItems: "archive.entity.inventoryItems"
        case .consumptionLogs: "archive.entity.consumptionLogs"
        case .inventoryEvents: "archive.entity.inventoryEvents"
        case .shoppingListItems: "archive.entity.shoppingListItems"
        }
    }
}
