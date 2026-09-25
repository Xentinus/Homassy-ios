import CloudKit
import CoreData
import Foundation

/// Local mode (no CLOUDKIT_ENABLED) and UI tests: the NSPersistentCloudKitContainer sharing surface,
/// simulated in-process. It never calls CloudKit. A shared household gets one fake CKShare in the zone
/// `local.share.<publicId>`; the shared publicIds are kept in `defaults`, so roles survive a relaunch.
@MainActor
public final class LocalCloudSharing: CloudSharing {
    public nonisolated static let sharedSpaceIDsKey = "localSharedSpaceIDs"
    public nonisolated static let zonePrefix = "local.share."

    public let persistence: PersistenceController
    private let defaults: UserDefaults
    private var shares: [UUID: CKShare] = [:]

    public init(persistence: PersistenceController, defaults: UserDefaults = .standard) {
        self.persistence = persistence
        self.defaults = defaults
    }

    public var isCloudBacked: Bool { false }

    public nonisolated static func zoneID(for spacePublicId: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zonePrefix + spacePublicId.uuidString, ownerName: CKCurrentUserDefaultName)
    }

    private var sharedIDs: Set<UUID> {
        get { Set((defaults.stringArray(forKey: Self.sharedSpaceIDsKey) ?? []).compactMap(UUID.init(uuidString:))) }
        set { defaults.set(newValue.map(\.uuidString).sorted(), forKey: Self.sharedSpaceIDsKey) }
    }

    private func localShare(for spacePublicId: UUID) -> CKShare {
        if let share = shares[spacePublicId] { return share }
        let share = CKShare(recordZoneID: Self.zoneID(for: spacePublicId))
        share.publicPermission = .none
        shares[spacePublicId] = share
        return share
    }

    private func space(for objectID: NSManagedObjectID) -> Space? {
        guard !objectID.isTemporaryID else { return nil }
        return (try? persistence.viewContext.existingObject(with: objectID)) as? Space
    }

    public func share(_ objects: [NSManagedObject], to existing: CKShare?) async throws -> CKShare {
        guard let space = objects.compactMap({ $0 as? Space }).first, space.kind == .household else {
            throw SharingError.personalSpace
        }
        guard space.objectID.persistentStore === persistence.privateStore else { throw SharingError.notOwner }
        if let existing { shares[space.publicId] = existing }
        sharedIDs.insert(space.publicId)
        return localShare(for: space.publicId)
    }

    public func share(forObjectWith objectID: NSManagedObjectID) -> CKShare? {
        guard let space = space(for: objectID), !space.isDeleted, sharedIDs.contains(space.publicId) else { return nil }
        return localShare(for: space.publicId)
    }

    public func shares(in store: NSPersistentStore) throws -> [CKShare] {
        guard store === persistence.privateStore else { return [] }      // nothing is ever joined locally
        let request = NSFetchRequest<Space>(entityName: "Space")
        request.affectedStores = [store]
        let ids = sharedIDs
        return try persistence.viewContext.fetch(request)
            .filter { ids.contains($0.publicId) }
            .map { localShare(for: $0.publicId) }
    }

    /// Every local household is owned by the user, so everything is editable.
    public func canUpdateRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool { true }

    /// Nothing is exported to CloudKit in local mode.
    public func recordZoneID(forObjectWith objectID: NSManagedObjectID) -> CKRecordZone.ID? { nil }

    public func persistUpdatedShare(_ share: CKShare, in store: NSPersistentStore) async throws -> CKShare { share }

    /// The local equivalent of a zone purge: delete the space's object graph and forget the share.
    public func purgeObjectsAndRecordsInZone(with zoneID: CKRecordZone.ID, in store: NSPersistentStore) async throws {
        guard zoneID.zoneName.hasPrefix(Self.zonePrefix),
              let id = UUID(uuidString: String(zoneID.zoneName.dropFirst(Self.zonePrefix.count))) else { return }
        let context = persistence.viewContext
        let request = NSFetchRequest<Space>(entityName: "Space")
        request.predicate = NSPredicate(format: "publicId == %@", id as CVarArg)
        request.affectedStores = [store]
        for space in try context.fetch(request) {
            for objectID in ObjectGraph.objectIDs(reachableFrom: space) {
                context.delete(try context.existingObject(with: objectID))
            }
        }
        if context.hasChanges { try context.save() }
        sharedIDs.remove(id)
        shares[id] = nil
    }

    public func acceptShareInvitations(from invitations: [any ShareInvitation], into store: NSPersistentStore) async throws {
        throw SharingError.cloudUnavailable
    }
}
