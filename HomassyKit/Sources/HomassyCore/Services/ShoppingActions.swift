import Foundation

/// Undoable shopping changes for the five-second undo toast (spec §6.4).
@MainActor
public enum ShoppingActions {
    /// Flips the purchase state now; `commit` saves, `revert` restores the previous state.
    public static func togglePurchased(_ item: ShoppingListItem, service: ShoppingService) -> UndoableAction {
        let name = ShoppingService.displayName(of: item)
        let wasPurchased = item.isPurchased
        let previousPurchasedAt = item.purchasedAt
        let previousUpdatedAt = item.updatedAt
        let previousUpdatedBy = item.updatedBy

        service.applyPurchased(item, !wasPurchased)

        return UndoableAction(
            title: wasPurchased ? UndoTitle.unpurchased(name) : UndoTitle.purchased(name),
            kind: .purchase,
            entityIDs: [item.publicId],
            revert: {
                guard !item.isGone else { return }
                item.isPurchased = wasPurchased
                item.purchasedAt = previousPurchasedAt
                item.updatedAt = previousUpdatedAt
                item.updatedBy = previousUpdatedBy
                try? service.save()
            },
            commit: { try service.save() }
        )
    }

    /// Hides the item now; `commit` deletes it, `revert` shows it again. Core Data is untouched
    /// until commit, so undo never has to recreate a record (and its CloudKit record).
    public static func deleteItem(_ item: ShoppingListItem, service: ShoppingService,
                                  pending: PendingDeletions) -> UndoableAction {
        pending.deletion(of: item.publicId, title: UndoTitle.removed(ShoppingService.displayName(of: item))) {
            guard !item.isGone else { return }
            try service.deleteItem(item)
        }
    }
}
