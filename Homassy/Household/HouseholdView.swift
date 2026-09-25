import HomassyCore
import SwiftUI

/// The Household tab root: settings of the selected space. P2-05 adds storage locations;
/// P5-01 adds sharing and delete/leave, P5-03 members, P5-05 the iCloud status and the sync problem callout.
struct HouseholdView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(SyncStatusModel.self) private var syncStatus

    var body: some View {
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

            if let space = services.activeSpace(selectedID: selection.selectedSpaceID) {
                HouseholdSpaceSections(space: space)
            }
        }
        .navigationTitle(AppTab.household.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { SpaceSwitcher() }
        }
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    NavigationStack { HouseholdView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.syncStatus)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    NavigationStack { HouseholdView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.syncStatus)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
}
#endif
