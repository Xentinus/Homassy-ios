import Foundation

/// Undoable shopping list changes for the five-second undo toast (spec §6.4). Purchases are `ShoppingPurchase`.
@MainActor
public enum ShoppingActions {
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
