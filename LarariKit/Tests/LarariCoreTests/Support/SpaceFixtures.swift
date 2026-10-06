import CloudKit
import CoreData
import Foundation
@testable import LarariCore

/// Share lookup that reports a space as shared once `markShared` was called for it.
@MainActor
final class FakeShareLookup: ShareLookup {
    private(set) var sharedSpaceIDs: Set<UUID> = []

    func markShared(_ space: Space) {
        sharedSpaceIDs.insert(space.publicId)
    }

    func share(for space: Space) -> CKShare? {
        guard sharedSpaceIDs.contains(space.publicId) else { return nil }
        let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.share.\(space.publicId.uuidString)",
                                   ownerName: CKCurrentUserDefaultName)
        return CKShare(recordZoneID: zone)
    }
}

@MainActor
struct SpaceFixture {
    let persistence: PersistenceController
    let sharing: FakeShareLookup
    let store: SpaceStore

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        sharing = FakeShareLookup()
        store = SpaceStore(persistence: persistence, sharing: sharing)
    }

    var context: NSManagedObjectContext { persistence.viewContext }

    /// Inserts any entity straight into `persistentStore`, bypassing `SpaceStore`, with explicit identity fields.
    func make<T: LarariEntity>(_ type: T.Type,
                                in persistentStore: NSPersistentStore,
                                publicId: UUID = UUID(),
                                createdAt: Date = .now,
                                by user: String = "_tester") -> T {
        let object = SpaceStore.makeObject(type, in: context)
        context.assign(object, to: persistentStore)
        object.publicId = publicId
        object.createdAt = createdAt
        object.updatedAt = createdAt
        object.createdBy = user
        object.updatedBy = user
        return object
    }

    func makeSpace(_ name: String,
                   kind: SpaceKind = .household,
                   sortOrder: Int = 0,
                   in persistentStore: NSPersistentStore? = nil,
                   publicId: UUID = UUID(),
                   createdAt: Date = .now) -> Space {
        let space = make(Space.self, in: persistentStore ?? persistence.privateStore,
                         publicId: publicId, createdAt: createdAt)
        space.name = name
        space.kind = kind
        space.sortOrder = numericCast(sortOrder)
        return space
    }

    func count(_ entityName: String) throws -> Int {
        try context.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))
    }
}
