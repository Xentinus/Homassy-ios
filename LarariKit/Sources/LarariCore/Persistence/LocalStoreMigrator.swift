import CoreData
import Foundation

public enum LocalStoreMigrationResult: Equatable, Sendable {
    /// No local `Private.sqlite`.
    case nothingToMigrate
    /// The App Group store already exists; the local store is left untouched.
    case destinationExists
    case migrated(objectCount: Int)
}

/// Moves the local-mode store (README "Local development mode") into the CloudKit store location,
/// before NSPersistentCloudKitContainer loads it, and adopts the `_localDeveloper` stamps afterwards (C-01).
@MainActor
public enum LocalStoreMigrator {
    public static let pendingAdoptionKey = "pendingLocalDataAdoption"
    public static let backupSuffix = "-local-backup"

    /// Copies `<source>/Private.sqlite` into `<destination>/Private.sqlite` (history on, no CloudKit options),
    /// then renames `<source>` to `<source>-local-backup`. Must run before the CloudKit container loads.
    /// The local `Shared.sqlite` is always empty (nothing can be joined in local mode), so it is not copied.
    public static func migrate(from source: URL, to destination: URL,
                               fileManager: FileManager = .default) throws -> LocalStoreMigrationResult {
        let sourceStore = source.appending(path: PersistenceController.privateFileName)
        let destinationStore = destination.appending(path: PersistenceController.privateFileName)
        guard fileManager.fileExists(atPath: sourceStore.path) else { return .nothingToMigrate }
        guard !fileManager.fileExists(atPath: destinationStore.path) else { return .destinationExists }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let options: [AnyHashable: Any] = [NSPersistentHistoryTrackingKey: true as NSNumber,
                                           NSPersistentStoreRemoteChangeNotificationPostOptionKey: true as NSNumber]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: LarariModel.shared)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: sourceStore, options: options)
        let migrated = try coordinator.migratePersistentStore(store, to: destinationStore, options: options, type: .sqlite)

        let context = NSManagedObjectContext(.mainQueue)
        context.persistentStoreCoordinator = coordinator
        var count = 0
        for entity in LarariModel.shared.entities {
            guard let name = entity.name else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.affectedStores = [migrated]
            request.includesSubentities = false
            count += try context.count(for: request)
        }
        try coordinator.remove(migrated)

        let backup = source.deletingLastPathComponent()
            .appending(path: source.lastPathComponent + backupSuffix, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
        try fileManager.moveItem(at: source, to: backup)
        return .migrated(objectCount: count)
    }

    /// Rewrites `_localDeveloper` stamps to `userRecordName` and re-keys the Personal space, so bootstrap never
    /// creates a second Personal space and no row reads as someone else's change. Returns the number of objects
    /// changed; 0 when there is nothing left to adopt. Saves the context.
    @discardableResult
    public static func adoptLocalData(in persistence: PersistenceController,
                                      from localUserRecordName: String = LocalAccountStatusProvider.userRecordName,
                                      to userRecordName: String) throws -> Int {
        let context = persistence.viewContext
        var changed = Set<NSManagedObjectID>()
        for entity in LarariModel.shared.entities {
            guard let name = entity.name else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.predicate = NSPredicate(format: "createdBy == %@ OR updatedBy == %@", localUserRecordName, localUserRecordName)
            for object in try context.fetch(request) {
                if object.value(forKey: "createdBy") as? String == localUserRecordName { object.setValue(userRecordName, forKey: "createdBy") }
                if object.value(forKey: "updatedBy") as? String == localUserRecordName { object.setValue(userRecordName, forKey: "updatedBy") }
                changed.insert(object.objectID)
            }
        }
        let members = NSFetchRequest<Member>(entityName: "Member")
        members.predicate = NSPredicate(format: "userRecordName == %@ OR colorSeed == %@", localUserRecordName, localUserRecordName)
        for member in try context.fetch(members) {
            if member.userRecordName == localUserRecordName { member.userRecordName = userRecordName }
            if member.colorSeed == localUserRecordName { member.colorSeed = userRecordName }
            changed.insert(member.objectID)
        }
        let personal = NSFetchRequest<Space>(entityName: "Space")
        personal.predicate = NSPredicate(format: "publicId == %@", SpaceStore.personalSpaceID(for: localUserRecordName) as CVarArg)
        for space in try context.fetch(personal) {
            space.publicId = SpaceStore.personalSpaceID(for: userRecordName)
            changed.insert(space.objectID)
        }
        if context.hasChanges { try context.save() }
        return changed.count
    }
}
