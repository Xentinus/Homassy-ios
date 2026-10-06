import Foundation
import Observation

/// Objects the user deleted whose undo window is still open. Lists filter these ids out, so the
/// delete looks immediate while nothing has been deleted or saved yet (spec §3.1, §6.4).
@MainActor
@Observable
public final class PendingDeletions {
    public private(set) var ids: Set<UUID> = []

    public init() {}

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }
    public func hide(_ id: UUID) { ids.insert(id) }
    public func restore(_ id: UUID) { ids.remove(id) }

    /// Hides `id` now and returns the action for `UndoQueue.enqueue`. `perform` runs on commit.
    public func deletion(of id: UUID, title: String,
                         perform: @escaping @MainActor () throws -> Void) -> UndoableAction {
        hide(id)
        return UndoableAction(
            title: title,
            kind: .delete,
            entityIDs: [id],
            revert: { [weak self] in self?.restore(id) },
            commit: { [weak self] in
                defer { self?.restore(id) }
                try perform()
            })
    }
}
