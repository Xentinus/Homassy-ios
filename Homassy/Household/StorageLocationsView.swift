import CoreData
import HomassyCore
import SwiftUI

struct StorageLocationsView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(UndoQueue.self) private var undoQueue
    @State private var model: StorageLocationsModel?
    @State private var editing: EditTarget?
    @State private var deleteFeedback = 0

    enum EditTarget: Identifiable {
        case new
        case existing(UUID)
        var id: String {
            switch self {
            case .new: "new"
            case .existing(let id): id.uuidString
            }
        }
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("storageLocations.title")
        .task(id: selection.selectedSpaceID) { rebuildModel() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in
            model?.reload()
        }
        .sensoryFeedback(.impact, trigger: deleteFeedback)
    }

    @ViewBuilder
    private func content(_ model: StorageLocationsModel) -> some View {
        List {
            ForEach(model.visibleRows) { row in
                Button { editing = .existing(row.id) } label: { StorageLocationRowView(row: row) }
                    .buttonStyle(.plain)
                    .disabled(!model.canEdit)
                    .accessibilityIdentifier("storageLocation.row.\(row.name)")
                    .swipeActions(edge: .trailing) {
                        if model.canEdit {
                            Button(role: .destructive) { delete(row, model: model) } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                        }
                    }
            }
            .onMove(perform: moveHandler(for: model))
        }
        .overlay {
            if model.visibleRows.isEmpty {
                ContentUnavailableView("storageLocations.empty.title", systemImage: "archivebox",
                                       description: Text("storageLocations.empty.message"))
            }
        }
        .toolbar {
            if model.canEdit {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = .new } label: { Label("storageLocations.add", systemImage: "plus") }
                        .accessibilityIdentifier("storageLocations.add")
                }
            }
        }
        .sheet(item: $editing) { target in
            StorageLocationFormSheet(model: formModel(for: target, in: model))
        }
        .alert("common.error", isPresented: Binding(get: { model.errorMessage != nil },
                                                    set: { if !$0 { model.dismissError() } })) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func moveHandler(for model: StorageLocationsModel) -> ((IndexSet, Int) -> Void)? {
        guard model.canEdit else { return nil }
        return { source, destination in model.move(fromOffsets: source, toOffset: destination) }
    }

    private func rebuildModel() {
        guard let space = services.activeSpace(selectedID: selection.selectedSpaceID) else { return }
        let fresh = StorageLocationsModel(service: services.storageLocations, space: space, pending: services.pendingDeletions)
        fresh.reload()
        model = fresh
    }

    private func delete(_ row: StorageLocationRow, model: StorageLocationsModel) {
        guard let action = model.delete(row) else { return }
        undoQueue.enqueue(action)
        deleteFeedback += 1
    }

    private func formModel(for target: EditTarget, in model: StorageLocationsModel) -> StorageLocationFormModel {
        switch target {
        case .new:
            StorageLocationFormModel(mode: .create(model.space), service: services.storageLocations)
        case .existing(let id):
            if let location = model.location(for: id) {
                StorageLocationFormModel(mode: .edit(location), service: services.storageLocations)
            } else {
                StorageLocationFormModel(mode: .create(model.space), service: services.storageLocations)
            }
        }
    }
}

private struct StorageLocationRowView: View {
    let row: StorageLocationRow

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(row.color?.color ?? Color.secondary.opacity(0.3))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(row.name)
            if row.isFreezer {
                Image(systemName: "snowflake")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("storageLocations.form.freezer"))
            }
            Spacer()
            Text("storageLocations.itemCount \(row.itemCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    NavigationStack { StorageLocationsView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    NavigationStack { StorageLocationsView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
}
#endif
