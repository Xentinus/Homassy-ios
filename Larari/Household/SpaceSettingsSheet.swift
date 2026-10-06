import LarariCore
import SwiftUI

/// Settings of the selected space, opened from "Settings…" in the space menu (P1-07a, the Home app pattern,
/// user choice 2026-09-26). It replaces the app's former Household screen and keeps its sections: storage
/// locations (P2-05), members and sharing (P5-01…P5-03), iCloud and the sync problem callout (P5-05), backup
/// (P3-04) and support (X-03). Delete/Leave, when there is one, sits below Support at the very bottom (HIG,
/// user choice 2026-09-26). It always shows the space it was opened for, and closes itself when the selection
/// changes, for example after the household is deleted or left.
struct SpaceSettingsSheet: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(SyncStatusModel.self) private var syncStatus
    /// The switcher's own router: an import started here is presented by the shell once this sheet has closed.
    @Environment(ArchiveImportRouter.self) private var importRouter
    @Environment(\.dismiss) private var dismiss
    /// The shell's exporter sits under this sheet and cannot present over it, so the sheet exports by itself.
    @State private var exportTarget: Space?

    var body: some View {
        let space = services.activeSpace(selectedID: selection.selectedSpaceID)
        NavigationStack {
            List {
                if let problem = syncStatus.bannerProblem {
                    SyncProblemCallout(problem: problem)
                }
                Section {
                    NavigationLink {
                        StorageLocationsView()
                    } label: {
                        Label("storageLocations.title", systemImage: "archivebox")
                    }
                    .accessibilityIdentifier("household.storageLocations")
                } footer: {
                    Text("empty.household")
                }

                if let space {
                    HouseholdSpaceSections(space: space) {
                        SupportSection()
                    }
                } else {
                    SupportSection()
                }
            }
            .navigationTitle(Text(verbatim: space?.name ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: "common.done") { dismiss() }
                        .accessibilityIdentifier("space.settings.done")
                }
            }
        }
        .overlay(alignment: .bottom) { UndoToastOverlay() }
        .environment(\.requestExport, ExportRequestAction { exportTarget = $0 })
        .archiveExporting($exportTarget)
        .onChange(of: selection.selectedSpaceID) { dismiss() }
        .onChange(of: importRouter.pending?.id) { _, id in
            if id != nil { dismiss() }
        }
        .onChange(of: importRouter.errorMessage) { _, message in
            if message != nil { dismiss() }
        }
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    Text(verbatim: "")
        .sheet(isPresented: .constant(true)) { SpaceSettingsSheet() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.syncStatus)
        .environment(model.services!.storeDirectory)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "LarariPreview")!))
}
#endif
