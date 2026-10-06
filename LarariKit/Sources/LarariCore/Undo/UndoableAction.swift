import Foundation

public enum UndoKind: String, Sendable, CaseIterable {
    /// Any change that is not one of the specific kinds below. The default; collapses to "N changes".
    case generic
    case delete, purchase, move, consume
}

/// A change that has already been applied to the view context and waits for its undo window.
public struct UndoableAction: Identifiable {
    public let id: UUID
    public let title: String
    public let kind: UndoKind
    /// The `publicId`s this action touches. Drives overlap replacement and `UndoQueue.isPending(_:)`.
    public let entityIDs: Set<UUID>
    /// Restores what the change did. Never called after `commit` succeeded.
    public let revert: @MainActor () -> Void
    /// Makes the change permanent, typically `try context.save()`.
    public let commit: @MainActor () throws -> Void

    public init(id: UUID = UUID(),
                title: String,
                kind: UndoKind = .generic,
                entityIDs: [UUID] = [],
                revert: @escaping @MainActor () -> Void,
                commit: @escaping @MainActor () throws -> Void) {
        self.id = id
        self.title = title
        self.kind = kind
        self.entityIDs = Set(entityIDs)
        self.revert = revert
        self.commit = commit
    }
}
