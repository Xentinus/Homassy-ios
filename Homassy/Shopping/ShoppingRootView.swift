import CoreData
import HomassyCore
import SwiftUI

/// Navigation value for an open shopping list. Codable, so the tab's restored path reopens it after
/// rotation and relaunch (`TabNavigationStack` keeps the path in scene storage).
struct ShoppingListRoute: Hashable, Codable {
    let id: UUID
}

/// The Shopping tab root: the active space's lists and the list detail.
struct ShoppingRootView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection

    var body: some View {
        Group {
            if let space = currentSpace {
                ShoppingListsView(space: space, services: services)
                    .id(space.objectID)
            } else {
                ContentUnavailableView("shopping.noSpace", systemImage: "cart")
                    .navigationTitle(Text("shopping.lists.title"))
            }
        }
        .navigationDestination(for: ShoppingListRoute.self) { ShoppingListDestination(id: $0.id) }
    }

    private var currentSpace: Space? { services.activeSpace(selectedID: selection.selectedSpaceID) }
}

/// Resolves a restored or tapped list id in the active space.
private struct ShoppingListDestination: View {
    let id: UUID

    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(UndoQueue.self) private var undoQueue

    var body: some View {
        if let list {
            ShoppingListDetailView(list: list, services: services, undoQueue: undoQueue)
                .id(list.objectID)
        } else {
            ContentUnavailableView("shopping.list.missing", systemImage: "questionmark.folder")
        }
    }

    private var list: ShoppingList? {
        guard let space = services.activeSpace(selectedID: selection.selectedSpaceID) else { return nil }
        return (try? services.shopping.lists(in: space))?.first { $0.publicId == id }
    }
}
