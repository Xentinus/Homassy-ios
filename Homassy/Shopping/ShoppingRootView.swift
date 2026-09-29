import CoreData
import HomassyCore
import SwiftUI

/// The Shopping tab root (P4-03a): the active space's Shopping home. There is no list drill-down any more.
/// A path restored from before P4-03a names the removed `ShoppingListRoute`, so `NavigationPathCoding.decode`
/// fails and returns an empty path.
struct ShoppingRootView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(UndoQueue.self) private var undoQueue
    @Environment(StoreDirectory.self) private var directory

    var body: some View {
        if let space = currentSpace {
            ShoppingHomeView(space: space, services: services, undoQueue: undoQueue, directory: directory)
                .id(space.objectID)
        } else {
            ContentUnavailableView("shopping.noSpace", systemImage: "cart")
                .navigationTitle(Text("shopping.lists.title"))
        }
    }

    private var currentSpace: Space? { services.activeSpace(selectedID: selection.selectedSpaceID) }
}
