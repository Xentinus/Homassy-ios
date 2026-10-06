import CoreData
import Foundation

/// Undoable inventory changes for the toast. Each factory applies the change in memory and returns
/// the action to enqueue; `commit` saves, `revert` restores the previous values, removes what the
/// change created (log, history event, the split half of a partial move) and saves.
@MainActor
public enum InventoryActions {
    public static func consume(_ item: InventoryItem, quantity: Decimal, service: InventoryService) throws -> UndoableAction {
        let snapshot = ItemSnapshot(item)
        let change = try service.applyConsume(item, quantity: quantity, commit: false)
        return action(title: UndoTitle.consumed(item.product?.name ?? ""), kind: .consume, item: item, snapshot: snapshot,
                      created: [change.log, change.event], service: service)
    }

    public static func markUsedUp(_ item: InventoryItem, service: InventoryService) throws -> UndoableAction {
        let snapshot = ItemSnapshot(item)
        let change = try service.applyConsume(item, quantity: item.quantity, commit: false)
        return action(title: UndoTitle.usedUp(item.product?.name ?? ""), kind: .consume, item: item, snapshot: snapshot,
                      created: [change.log, change.event], service: service)
    }

    public static func move(_ item: InventoryItem, to location: StorageLocation?, service: InventoryService) throws -> UndoableAction {
        try move(item, quantity: nil, to: location, service: service)
    }

    /// A partial move: `quantity` less than the item's splits it; undo merges it back.
    public static func move(_ item: InventoryItem, quantity: Decimal, to location: StorageLocation?,
                            service: InventoryService) throws -> UndoableAction {
        try move(item, quantity: Optional(quantity), to: location, service: service)
    }

    public static func delete(_ item: InventoryItem, service: InventoryService, pending: PendingDeletions) throws -> UndoableAction {
        guard !item.isGone, let space = service.space(of: item) else { throw ServiceError.notFound }
        guard service.canEdit(space) else { throw ServiceError.readOnlySpace }
        return pending.deletion(of: item.publicId, title: UndoTitle.removed(item.product?.name ?? "")) {
            guard !item.isGone else { return }
            try service.delete(item)
        }
    }

    private static func move(_ item: InventoryItem, quantity: Decimal?, to location: StorageLocation?,
                             service: InventoryService) throws -> UndoableAction {
        let snapshot = ItemSnapshot(item)
        let change = try service.applyMove(item, quantity: quantity, to: location, commit: false)
        return action(title: UndoTitle.moved(item.product?.name ?? ""), kind: .move, item: item, snapshot: snapshot,
                      created: [change.event, change.split].compactMap { $0 }, service: service)
    }

    private static func action(title: String, kind: UndoKind, item: InventoryItem, snapshot: ItemSnapshot,
                               created: [NSManagedObject], service: InventoryService) -> UndoableAction {
        UndoableAction(
            title: title,
            kind: kind,
            entityIDs: [item.publicId],
            revert: {
                if !item.isGone { snapshot.restore(on: item) }
                created.forEach(service.discard)
                try? service.saveIfNeeded()
            },
            commit: { try service.saveIfNeeded() })
    }
}

/// The fields an undoable inventory action can change.
@MainActor
struct ItemSnapshot {
    let quantity: Decimal
    let isFullyConsumed: Bool
    let consumedAt: Date?
    let storageLocation: StorageLocation?
    let updatedAt: Date
    let updatedBy: String

    init(_ item: InventoryItem) {
        quantity = item.quantity
        isFullyConsumed = item.isFullyConsumed
        consumedAt = item.consumedAt
        storageLocation = item.storageLocation
        updatedAt = item.updatedAt
        updatedBy = item.updatedBy
    }

    func restore(on item: InventoryItem) {
        item.quantity = quantity
        item.isFullyConsumed = isFullyConsumed
        item.consumedAt = consumedAt
        item.storageLocation = storageLocation.flatMap { $0.isGone ? nil : $0 }
        item.updatedAt = updatedAt
        item.updatedBy = updatedBy
    }
}
