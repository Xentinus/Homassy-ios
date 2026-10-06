import CoreData
import Foundation

/// The archive part of `ServiceContainer` (`services.archive`). Exporters and importers are cheap and
/// short-lived, so the container hands out fresh ones instead of keeping them.
@MainActor
public final class ArchiveServices {
    public let persistence: PersistenceController
    public let spaceStore: SpaceStore
    public let userRecordName: String
    private let canEdit: @MainActor (Space) -> Bool

    public init(persistence: PersistenceController, spaceStore: SpaceStore, userRecordName: String,
                canEdit: @escaping @MainActor (Space) -> Bool = { _ in true }) {
        self.persistence = persistence
        self.spaceStore = spaceStore
        self.userRecordName = userRecordName
        self.canEdit = canEdit
    }

    /// The user owns everything in the private store: Personal, own households, unshared imports.
    /// Joined households live in the shared store.
    public func ownsSpace(_ space: Space) -> Bool {
        spaceStore.store(for: space) === persistence.privateStore
    }

    public func makeExporter() -> ArchiveExporter {
        ArchiveExporter(context: persistence.viewContext, userRecordName: userRecordName,
                        ownsSpace: { [spaceStore, persistence] space in
                            spaceStore.store(for: space) === persistence.privateStore
                        })
    }

    public func makeImporter() -> ArchiveImporter {
        ArchiveImporter(persistence: persistence, spaceStore: spaceStore, userRecordName: userRecordName, canEdit: canEdit)
    }
}
