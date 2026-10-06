import CloudKit
import CoreData
import Foundation
@testable import LarariCore

@MainActor
enum SharingFixtures {
    static func insertSpace(
        named name: String,
        kind: SpaceKind = .household,
        into store: NSPersistentStore,
        of persistence: PersistenceController,
        by userRecordName: String
    ) throws -> Space {
        let context = persistence.viewContext
        let space = NSEntityDescription.insertNewObject(forEntityName: "Space", into: context) as! Space
        context.assign(space, to: store)
        space.publicId = UUID()
        space.createdAt = .now
        space.createdBy = userRecordName
        space.stamp(by: userRecordName)
        space.name = name
        space.kind = kind
        try context.save()
        return space
    }

    static func fetchSpace(_ publicId: UUID, in persistence: PersistenceController) throws -> Space? {
        let request = NSFetchRequest<Space>(entityName: "Space")
        request.predicate = NSPredicate(format: "publicId == %@", publicId as CVarArg)
        return try persistence.viewContext.fetch(request).first
    }

    static func members(of space: Space, in persistence: PersistenceController) throws -> [Member] {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "space == %@", space)
        return try persistence.viewContext.fetch(request)
    }

    nonisolated static func zoneID(owner: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.share.\(UUID().uuidString)", ownerName: owner)
    }
}
