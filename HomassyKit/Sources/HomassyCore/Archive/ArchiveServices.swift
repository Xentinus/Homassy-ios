import CoreData
import Foundation

/// The archive part of `ServiceContainer` (`services.archive`). Exporters and importers are cheap and
/// short-lived, so the container hands out fresh ones instead of keeping them.
@MainActor
public final class ArchiveServices {
    public let persistence: PersistenceController
    public let spaceStore: SpaceStore
    public let userRecordName: String

    public init(persistence: PersistenceController, spaceStore: SpaceStore, userRecordName: String) {
        self.persistence = persistence
        self.spaceStore = spaceStore
        self.userRecordName = userRecordName
    }

    public func makeExporter() -> ArchiveExporter {
        ArchiveExporter(context: persistence.viewContext)
    }

    public func makeImporter() -> ArchiveImporter {
        ArchiveImporter(persistence: persistence, spaceStore: spaceStore, userRecordName: userRecordName)
    }
}
