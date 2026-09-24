import HomassyCore
import SwiftUI

/// The Household tab root: settings of the selected space. P2-05 adds storage locations;
/// P5 adds members, sharing and sync status.
struct HouseholdView: View {
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
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    NavigationStack { HouseholdView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
}
#endif
