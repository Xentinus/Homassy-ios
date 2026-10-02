import CoreData
import HomassyCore
import SwiftUI

/// The column of the wide cards (P2-08d, user pick 5A, Mail and Reminders on iPad): at most this wide, centred.
enum CardColumn {
    static let maxWidth: CGFloat = 680
}

/// The long-press menu of a product card on Inventory and Search (P2-08d, user pick 3B, the Photos / Music pattern):
/// add stock, add to a shopping list, favourite. Nothing destructive; delete stays in the product detail
/// (user rule 2026-09-24). One per screen; the cards set a target, the screen's sheets open it.
@Observable
final class ProductCardActions {
    struct Target: Identifiable { let id: UUID }

    var stockTarget: Target?
    var listTarget: Target?
    var errorMessage: String?
    /// The space's shopping lists; Listára is disabled when there are none.
    var shoppingLists: [ShoppingList] = []
}

extension View {
    /// The card's long-press menu and the same actions for VoiceOver. Nothing when the space is read-only.
    func productCardMenu(_ card: ProductCardData, actions: ProductCardActions, canEdit: Bool) -> some View {
        modifier(ProductCardMenu(card: card, actions: actions, canEdit: canEdit))
    }

    /// The sheets and the error alert the card menu opens. Attach once per screen.
    func productCardActionSheets(_ actions: ProductCardActions, space: Space?) -> some View {
        modifier(ProductCardActionSheets(actions: actions, space: space))
    }
}

private struct ProductCardMenu: ViewModifier {
    let card: ProductCardData
    let actions: ProductCardActions
    let canEdit: Bool
    @Environment(ServiceContainer.self) private var services

    func body(content: Content) -> some View {
        content
            .contextMenu { if canEdit { items(forAccessibility: false) } }
            .accessibilityActions { if canEdit { items(forAccessibility: true) } }
    }

    /// `.disabled` is not reliably honoured for VoiceOver custom actions, so the accessibility copy leaves Listára
    /// out when there is no list to add to; the context menu shows it disabled.
    @ViewBuilder private func items(forAccessibility: Bool) -> some View {
        Button { actions.stockTarget = .init(id: card.id) } label: {
            Label("stock.title.add", systemImage: "plus")
        }
        if !(forAccessibility && actions.shoppingLists.isEmpty) {
            Button {
                guard !actions.shoppingLists.isEmpty else { return }
                actions.listTarget = .init(id: card.id)
            } label: {
                Label("product.detail.addToList", systemImage: "cart.badge.plus")
            }
            .disabled(actions.shoppingLists.isEmpty)
        }
        Button {
            do { try services.products.toggleFavorite(publicId: card.id) } catch {
                actions.errorMessage = error.localizedDescription
            }
        } label: {
            if card.isFavorite {
                Label("product.card.unfavorite", systemImage: "heart.slash")
            } else {
                Label("product.field.favorite", systemImage: "heart")
            }
        }
    }
}

private struct ProductCardActionSheets: ViewModifier {
    @Bindable var actions: ProductCardActions
    let space: Space?
    @Environment(ServiceContainer.self) private var services

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.stockTarget) { target in
                if let space { StockAddSheet.adding(target.id, in: space, services: services) }
            }
            .sheet(item: $actions.listTarget) { target in
                if let product = try? services.products.product(publicId: target.id) {
                    AddItemSheet(lists: actions.shoppingLists, preselected: nil, services: services, product: product)
                }
            }
            .alert("common.error", isPresented: Binding(get: { actions.errorMessage != nil },
                                                        set: { if !$0 { actions.errorMessage = nil } })) {
                Button("common.ok", role: .cancel) {}
            } message: { Text(actions.errorMessage ?? "") }
            .task(id: space?.objectID) { reloadLists() }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                            object: services.context)) { _ in reloadLists() }
    }

    private func reloadLists() {
        actions.shoppingLists = space.flatMap { try? services.shopping.lists(in: $0) } ?? []
    }
}
