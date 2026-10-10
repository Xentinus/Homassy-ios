import CloudKit
import CoreData
import Foundation

public enum HouseholdRole: String, Sendable, Equatable {
    case owner, participant, notShared
}

public enum SharingError: Error, Equatable, LocalizedError {
    case personalSpace
    case notOwner
    case notParticipant
    case notShared
    case createdButNotShared(spacePublicId: UUID)
    case cloudUnavailable

    public var errorDescription: String? {
        switch self {
        case .personalSpace:
            String(localized: "sharing.error.personalSpace", defaultValue: "This isn't available for your Personal space.", bundle: .module)
        case .notOwner:
            String(localized: "sharing.error.notOwner", defaultValue: "Only the household's owner can do this.", bundle: .module)
        case .notParticipant:
            String(localized: "sharing.error.notParticipant", defaultValue: "You own this household. Delete it instead of leaving.", bundle: .module)
        case .notShared:
            String(localized: "sharing.error.notShared", defaultValue: "This household isn't shared yet.", bundle: .module)
        case .createdButNotShared:
            String(localized: "sharing.error.createdButNotShared", defaultValue: "The household was created but couldn't be shared yet. Try sharing it again in Settings, from the space menu.", bundle: .module)
        case .cloudUnavailable:
            String(localized: "sharing.error.cloudUnavailable", defaultValue: "Sharing needs iCloud — available in the released app.", bundle: .module)
        }
    }
}

@MainActor
public final class SharingService {
    public let userRecordName: String
    public let persistence: PersistenceController
    private let spaceStore: SpaceStore
    private let cloud: any CloudSharing

    public init(persistence: PersistenceController, spaceStore: SpaceStore, cloud: any CloudSharing, userRecordName: String) {
        self.persistence = persistence
        self.spaceStore = spaceStore
        self.cloud = cloud
        self.userRecordName = userRecordName
    }

    private var context: NSManagedObjectContext { persistence.viewContext }

    /// False in local mode (`LocalCloudSharing`): the UI shows "Sharing needs iCloud" instead of
    /// opening invitations or UICloudSharingController.
    public var isCloudBacked: Bool { cloud.isCloudBacked }

    // MARK: Create and share

    public func createHousehold(name: String, ownerDisplayName: String? = nil) async throws -> Space {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServiceError.nameRequired }

        let now = Date.now
        let space = NSEntityDescription.insertNewObject(forEntityName: "Space", into: context) as! Space
        context.assign(space, to: persistence.privateStore)
        space.publicId = UUID()
        space.createdAt = now
        space.createdBy = userRecordName
        space.stamp(by: userRecordName, now: now)
        space.name = trimmed
        space.kind = .household
        space.sortOrder = try nextHouseholdSortOrder()
        try context.save()          // permanent objectID first, so SpaceStore.store(for:) resolves the private store
        insertOwnerMember(in: space, displayName: ownerDisplayName ?? suggestedOwnerDisplayName() ?? "")
        try context.save()

        do {
            try await shareRoot(space, title: trimmed)
        } catch {
            throw SharingError.createdButNotShared(spacePublicId: space.publicId)
        }
        return space
    }

    /// Shares a household that exists only in the private store (imported archives, or a create
    /// whose share call failed). Returns the existing share if there already is one.
    @discardableResult
    public func shareExistingSpace(_ space: Space) async throws -> CKShare {
        guard space.kind == .household else { throw SharingError.personalSpace }
        // A fresh lookup, not the cache: a stale "not shared" here would create a second share (P5-06).
        if let existing = await cloud.fetchShare(forObjectWith: space.objectID) { return existing }
        guard spaceStore.store(for: space) === persistence.privateStore else { throw SharingError.notOwner }
        if try !hasOwnMember(in: space) {
            insertOwnerMember(in: space, displayName: suggestedOwnerDisplayName() ?? "")
        }
        if context.hasChanges { try context.save() }
        return try await shareRoot(space, title: space.name)
    }

    @discardableResult
    private func shareRoot(_ space: Space, title: String) async throws -> CKShare {
        let share = try await cloud.share([space], to: nil)
        share[CKShare.SystemFieldKey.title] = title
        share.publicPermission = .none
        return try await cloud.persistUpdatedShare(share, in: persistence.privateStore)
    }

    // MARK: Queries

    public func share(for space: Space) -> CKShare? {
        cloud.share(for: space)
    }

    public func role(for space: Space) -> HouseholdRole {
        guard space.kind == .household, cloud.share(for: space) != nil else { return .notShared }
        return spaceStore.store(for: space) === persistence.privateStore ? .owner : .participant
    }

    /// Everything in the private store (Personal, owned and unshared households) is editable.
    /// For joined households the share's permission decides.
    public func canEdit(_ space: Space) -> Bool {
        if spaceStore.store(for: space) === persistence.privateStore { return true }
        return cloud.canUpdateRecord(forManagedObjectWith: space.objectID)
    }

    public func space(withPublicId id: UUID) -> Space? {
        let request = NSFetchRequest<Space>(entityName: "Space")
        request.predicate = NSPredicate(format: "publicId == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// The display name the user most recently gave themselves in any space.
    public func suggestedOwnerDisplayName() -> String? {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "userRecordName == %@ AND displayName != %@", userRecordName, "")
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request).first)?.displayName
    }

    /// Exported objects of the space whose CloudKit zone differs from the share's zone.
    /// Must be empty; shown in a DEBUG row and checked in the manual checklist. Async: the zone lookups block.
    public func objectsOutsideShareZone(in space: Space) async -> [NSManagedObjectID] {
        guard let zoneID = await cloud.fetchShare(forObjectWith: space.objectID)?.recordID.zoneID else { return [] }
        var outside: [NSManagedObjectID] = []
        for id in ObjectGraph.objectIDs(reachableFrom: space) {
            if let recordZone = await cloud.fetchRecordZoneID(forObjectWith: id), recordZone != zoneID {
                outside.append(id)
            }
        }
        return outside.sorted { $0.uriRepresentation().absoluteString < $1.uriRepresentation().absoluteString }
    }

    // MARK: Leave and delete

    /// Participant: purging the zone in the shared store ends the participation and removes the
    /// local copy. The UI offers an export first.
    public func leave(_ space: Space) async throws {
        guard space.kind == .household, spaceStore.store(for: space) === persistence.sharedStore,
              let share = await cloud.fetchShare(forObjectWith: space.objectID) else {
            throw SharingError.notParticipant
        }
        try await purge(space, zoneID: share.recordID.zoneID, in: persistence.sharedStore)
    }

    /// Owner: purging the zone in the private store deletes the household for everyone.
    /// An unshared household is deleted locally.
    public func deleteHousehold(_ space: Space) async throws {
        guard space.kind == .household else { throw SharingError.personalSpace }
        switch role(for: space) {
        case .participant:
            throw SharingError.notOwner
        case .owner:
            guard let share = await cloud.fetchShare(forObjectWith: space.objectID) else { throw SharingError.notShared }
            try await purge(space, zoneID: share.recordID.zoneID, in: persistence.privateStore)
        case .notShared:
            for id in ObjectGraph.objectIDs(reachableFrom: space) {
                context.delete(try context.existingObject(with: id))
            }
            try context.save()
        }
    }

    private func purge(_ space: Space, zoneID: CKRecordZone.ID, in store: NSPersistentStore) async throws {
        let ids = ObjectGraph.objectIDs(reachableFrom: space)
        try await cloud.purgeObjectsAndRecordsInZone(with: zoneID, in: store)
        // The purge is a batch delete in the store; tell the view context so rows disappear now.
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: Array(ids)], into: [context])
        // Never ask the container about purged objects again: it raises an Objective-C exception (P0-01 rows 17–18).
        cloud.forget(Array(ids))
    }

    // MARK: UICloudSharingController hooks

    /// The sharing UI saved the share. NSPersistentCloudKitContainer also observes this itself
    /// (iOS 16.4+); persisting keeps its cached copy current immediately.
    public func saveUpdatedShare(_ share: CKShare, for space: Space) async throws {
        _ = try await cloud.persistUpdatedShare(share, in: spaceStore.store(for: space))
    }

    /// The sharing UI stopped sharing (owner) or removed the current user (participant).
    /// `zoneID` is captured when the controller opens, because the share may already be gone.
    public func sharingStopped(for space: Space, zoneID: CKRecordZone.ID, wasOwner: Bool) async throws {
        guard space.managedObjectContext != nil, !space.isDeleted else { return }
        if wasOwner {
            context.refresh(space, mergeChanges: true)   // data stays; household becomes unshared
            return
        }
        do {
            try await purge(space, zoneID: zoneID, in: persistence.sharedStore)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // The container already removed the zone.
        }
    }

    // MARK: Sync problems (P5-05)

    /// The joined household whose share lives in `zone`.
    public func space(inZone zone: ZoneReference) -> Space? {
        let request = NSFetchRequest<Space>(entityName: "Space")
        request.affectedStores = [persistence.sharedStore]
        let spaces = (try? context.fetch(request)) ?? []
        return spaces.first { space in
            guard let zoneID = cloud.share(for: space)?.recordID.zoneID else { return false }
            return ZoneReference(zoneID) == zone
        }
    }

    /// Removes a joined household's local copy after its zone disappeared. A zone that is
    /// already gone on the server is not an error.
    public func removeLocalCopy(of space: Space) async throws {
        guard spaceStore.store(for: space) === persistence.sharedStore else { throw SharingError.notParticipant }
        let zoneID = cloud.share(for: space)?.recordID.zoneID
        guard let zoneID else {
            for id in ObjectGraph.objectIDs(reachableFrom: space) {
                context.delete(try context.existingObject(with: id))
            }
            try context.save()
            return
        }
        do {
            try await purge(space, zoneID: zoneID, in: persistence.sharedStore)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // Already gone on the server; the container clears the local graph on its next pass.
        }
    }

    // MARK: Private

    private func nextHouseholdSortOrder() throws -> Int32 {
        let households = try spaceStore.allSpaces().filter { $0.kind == .household && $0.objectID.isTemporaryID == false }
        return (households.map(\.sortOrder).max() ?? -1) + 1
    }

    private func hasOwnMember(in space: Space) throws -> Bool {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "space == %@ AND userRecordName == %@", space, userRecordName)
        return try context.count(for: request) > 0
    }

    private func insertOwnerMember(in space: Space, displayName: String) {
        let member = spaceStore.insert(Member.self, in: space, by: userRecordName)
        member.space = space
        member.userRecordName = userRecordName
        member.colorSeed = userRecordName
        member.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
