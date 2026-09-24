import CloudKit
import CoreData
import CryptoKit
import Foundation

/// The single place that knows which store and share a space lives in.
@MainActor
public final class SpaceStore {
    /// Namespace for the Personal space's name-based UUID. Never change it: it would fork every user's Personal space.
    public nonisolated static let personalNamespace = UUID(uuidString: "6F1B8E0A-3C2D-4E5F-9A7B-1C2D3E4F5A6B")!

    private let persistence: PersistenceController
    private let sharing: any ShareLookup

    public init(persistence: PersistenceController, sharing: any ShareLookup) {
        self.persistence = persistence
        self.sharing = sharing
    }

    private var context: NSManagedObjectContext { persistence.viewContext }

    // MARK: Personal space

    /// UUID v5 (RFC 4122, SHA-1) of `userRecordName` in `personalNamespace`.
    public nonisolated static func personalSpaceID(for userRecordName: String) -> UUID {
        var input = withUnsafeBytes(of: personalNamespace.uuid) { Array($0) }
        input.append(contentsOf: Array(userRecordName.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Returns the user's Personal space, creating it in the private store on first use and merging
    /// copies that other devices created offline. Saves the view context.
    public func bootstrapPersonalSpace(userRecordName: String) throws -> Space {
        var personal = try personalSpaces()
        if personal.count > 1 {
            _ = try Deduplicator.mergeDuplicates(entityName: "Space", in: context)
            personal = try personalSpaces()
        }
        if let existing = personal.first {
            if context.hasChanges { try context.save() }
            return existing
        }

        let space = Self.makeObject(Space.self, in: context)
        context.assign(space, to: persistence.privateStore)
        stampNew(space, by: userRecordName)
        space.publicId = Self.personalSpaceID(for: userRecordName)
        space.name = String(localized: "space.personal.name", defaultValue: "Personal", bundle: .module,
                            comment: "Name of the private space every user has")
        space.kind = .personal
        space.sortOrder = 0
        try context.obtainPermanentIDs(for: [space])
        try context.save()
        return space
    }

    private func personalSpaces() throws -> [Space] {
        let request = NSFetchRequest<Space>(entityName: "Space")
        request.affectedStores = [persistence.privateStore]
        request.includesPendingChanges = true
        return try context.fetch(request)
            .filter { $0.kind == .personal && !$0.isDeleted }
            .sorted(by: Self.displayOrder)
    }

    // MARK: Listing

    /// Personal first, then households by `sortOrder`, then by creation date and `publicId`.
    public func allSpaces() throws -> [Space] {
        let request = NSFetchRequest<Space>(entityName: "Space")
        return try context.fetch(request).sorted(by: Self.displayOrder)
    }

    nonisolated static func displayOrder(_ lhs: Space, _ rhs: Space) -> Bool {
        let lhsRank = lhs.kind == .personal ? 0 : 1
        let rhsRank = rhs.kind == .personal ? 0 : 1
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if Int(lhs.sortOrder) != Int(rhs.sortOrder) { return Int(lhs.sortOrder) < Int(rhs.sortOrder) }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.publicId.uuidString < rhs.publicId.uuidString
    }

    // MARK: Creating objects

    /// Creates `type` in the store `space` lives in and stamps it. Does not set the relationship to
    /// `space` (the caller does, because not every entity points at `Space`) and does not save.
    public func insert<T: HomassyEntity>(_ type: T.Type, in space: Space, by userRecordName: String) -> T {
        let object = Self.makeObject(type, in: context)
        context.assign(object, to: store(for: space))
        stampNew(object, by: userRecordName)
        return object
    }

    public func store(for space: Space) -> NSPersistentStore {
        space.objectID.persistentStore ?? persistence.privateStore
    }

    public func isShared(_ space: Space) -> Bool {
        space.kind == .household && sharing.share(for: space) != nil
    }

    // MARK: Helpers

    private func stampNew(_ object: some HomassyEntity, by userRecordName: String) {
        let now = Date.now
        object.publicId = UUID()
        object.createdAt = now
        object.createdBy = userRecordName
        object.stamp(by: userRecordName, now: now)
        object.updatedAt = now
        object.updatedBy = userRecordName
    }

    /// Inserts an object of `type` using the entity whose class name matches, so it works with the
    /// programmatic model without relying on `NSManagedObject.entity()`.
    static func makeObject<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) -> T {
        let className = NSStringFromClass(type)
        guard let model = context.persistentStoreCoordinator?.managedObjectModel,
              let entity = model.entities.first(where: { $0.managedObjectClassName == className || $0.name == className })
        else {
            preconditionFailure("HomassyModel has no entity for class \(className)")
        }
        return T(entity: entity, insertInto: context)
    }
}
