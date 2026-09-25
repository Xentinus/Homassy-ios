import HomassyCore
import SwiftUI

/// The Household tab root: settings of the selected space. P2-05 adds storage locations;
/// P5-01 adds sharing and delete/leave; P5 adds members and sync status.
struct HouseholdView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection

    var body: some View {
        List {
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
        .environment(model.services!)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    NavigationStack { HouseholdView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
}
#endif
