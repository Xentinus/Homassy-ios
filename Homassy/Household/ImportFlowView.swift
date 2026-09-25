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
            ForEach(ArchiveSelection.Group.allCases, id: \.self) { group in
                groupRow(group, preview: preview)
                let options = model.options(for: group)
                if !options.isEmpty {
                    NavigationLink {
                        ImportRecordPicker(model: model, group: group)
                    } label: {
                        ImportRecordPicker.linkTitle(for: group, picked: model.pickedIDs(for: group).count,
                                                     total: options.count)
                    }
                    .disabled(model.phase == .importing)
                    .accessibilityIdentifier("import.pick.\(group.rawValue)")
                }
            }
        } header: {
            Text("archive.import.contents")
        } footer: {
            contentsFooter(preview)
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
                LabeledContent {
                    TextField("archive.import.newSpaceName", text: $model.newSpaceName)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("import.newSpaceName")
                } label: {
                    Text("archive.import.newSpaceName")
                }
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

    /// One group: its name, what else it holds, the count of its main entity and the toggle.
    @ViewBuilder private func groupRow(_ group: ArchiveSelection.Group, preview: ImportPreview) -> some View {
        let entity = Self.mainEntity(of: group)
        let counts = preview.counts(for: entity)
        // Someone else's household can leave no importable member at all (P5-02a).
        let isEmptyGroup = group == .members && model.options(for: .members).isEmpty
        let isOn = model.groups.contains(group) && (group != .stock || model.isStockAvailable) && !isEmptyGroup
        let automatic = isOn ? 0 : preview.autoIncluded[entity] ?? 0
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: group))
                Group {
                    switch group {
                    case .stock:
                        Text("archive.import.stock.detail \(preview.counts(for: .consumptionLogs).total) \(preview.counts(for: .inventoryEvents).total)")
                    case .products where preview.counts(for: .purchaseRecords).total > 0:
                        Text("archive.import.products.detail \(preview.counts(for: .purchaseRecords).total)")
                    case .shoppingLists:
                        Text("archive.import.lists.detail \(preview.counts(for: .shoppingListItems).total)")
                    default:
                        EmptyView()
                    }
                    if preview.isMerge && counts.total > 0 {
                        Text("archive.import.breakdown \(counts.toCreate) \(counts.toUpdate) \(counts.unchanged)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Group {
                if automatic > 0 {
                    Text("archive.import.auto \(automatic)")
                } else {
                    Text(counts.total, format: .number)
                }
            }
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("import.count.\(entity.rawValue)")
            Toggle(isOn: Binding(get: { isOn }, set: { model.setGroup(group, isOn: $0) })) {
                Text(Self.title(for: group))
            }
            .labelsHidden()
            .disabled(model.phase == .importing || (group == .stock && !model.isStockAvailable) || isEmptyGroup)
            .accessibilityIdentifier("import.group.\(group.rawValue)")
        }
    }

    @ViewBuilder private func contentsFooter(_ preview: ImportPreview) -> some View {
        let storage = preview.autoIncluded[.storageLocations] ?? 0
        let stores = preview.autoIncluded[.shoppingLocations] ?? 0
        VStack(alignment: .leading, spacing: 4) {
            if storage > 0 { Text("archive.import.auto.storageLocations \(storage)") }
            if stores > 0 { Text("archive.import.auto.shoppingLocations \(stores)") }
            if preview.unlinkedListItems > 0 { Text("archive.import.unlinked \(preview.unlinkedListItems)") }
            if preview.withheldMembers > 0 {
                Text("archive.import.members.withheld \(preview.withheldMembers)")
                    .accessibilityIdentifier("import.membersWithheld")
            }
            if model.isSelectionEmpty {
                Text("archive.import.nothingSelected").accessibilityIdentifier("import.nothingSelected")
            }
        }
    }

    static func mainEntity(of group: ArchiveSelection.Group) -> ArchiveEntity {
        switch group {
        case .products: .products
        case .stock: .inventoryItems
        case .storageLocations: .storageLocations
        case .shoppingLocations: .shoppingLocations
        case .shoppingLists: .shoppingLists
        case .members: .members
        }
    }

    static func title(for group: ArchiveSelection.Group) -> LocalizedStringKey {
        switch group {
        case .products: "archive.entity.products"
        case .stock: "archive.group.stock"
        case .storageLocations: "archive.entity.storageLocations"
        case .shoppingLocations: "archive.entity.shoppingLocations"
        case .shoppingLists: "archive.entity.shoppingLists"
        case .members: "archive.entity.members"
        }
    }
}
