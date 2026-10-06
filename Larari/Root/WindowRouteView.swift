import CoreData
import LarariCore
import SwiftUI

/// A window that shows one shopping list or one product (N-03, D4 = A; the Mail message window and Notes note
/// window pattern): no tab bar, its own navigation and undo toast. The window's space follows the item, so member
/// names and attribution resolve, without changing the space a new main window starts in. A deleted item shows a
/// "not found" state.
struct WindowRouteView: View {
    let route: WindowRoute

    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(UndoQueue.self) private var undoQueue
    @Environment(StoreDirectory.self) private var directory

    var body: some View {
        NavigationStack {
            content
        }
        .overlay(alignment: .bottom) { UndoToastOverlay() }
        .task(id: route) { selection.restore(itemSpaceID) }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case let .shoppingList(id):
            if let space = (try? services.shopping.list(publicId: id))?.space {
                ShoppingHomeView(space: space, services: services, undoQueue: undoQueue, directory: directory,
                                 pinnedListID: id)
                    .id(space.objectID)
            } else {
                ContentUnavailableView("shopping.list.missing", systemImage: "questionmark.folder")
            }
        case let .product(id):
            if (try? services.products.product(publicId: id)) != nil {
                ProductDetailView(productID: id)
            } else {
                ContentUnavailableView("product.detail.notFound", systemImage: "questionmark.square.dashed")
            }
        }
    }

    private var itemSpaceID: UUID? {
        switch route {
        case let .shoppingList(id): (try? services.shopping.list(publicId: id))?.space?.publicId
        case let .product(id): (try? services.products.product(publicId: id))?.space?.publicId
        }
    }
}
