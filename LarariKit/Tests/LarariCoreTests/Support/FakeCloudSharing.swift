import CloudKit
import CoreData
import Foundation
@testable import LarariCore

final class FakeShareInvitation: ShareInvitation {
    let containerIdentifier: String
    let sharedZoneID: CKRecordZone.ID
    init(containerIdentifier: String = "iCloud.app.larari", zoneID: CKRecordZone.ID = SharingFixtures.zoneID(owner: "_friend")) {
        self.containerIdentifier = containerIdentifier
        self.sharedZoneID = zoneID
    }
}

/// In-memory stand-in for NSPersistentCloudKitContainer's sharing API.
@MainActor
final class FakeCloudSharing: CloudSharing {
    let persistence: PersistenceController
    var sharesByRoot: [NSManagedObjectID: CKShare] = [:]
    var readOnlyObjectIDs: Set<NSManagedObjectID> = []
    var zoneOverrides: [NSManagedObjectID: CKRecordZone.ID] = [:]
    var shareError: Error?
    var persistError: Error?
    var purgeError: Error?
    var acceptError: Error?
    /// Simulates the import that follows an accepted invitation.
    var onAccept: ((any ShareInvitation) throws -> Void)?
    private(set) var shareCallCount = 0
    private(set) var persistedShares: [(share: CKShare, store: NSPersistentStore)] = []
    private(set) var purgedZones: [(zoneID: CKRecordZone.ID, store: NSPersistentStore)] = []
    private(set) var acceptCallCount = 0

    init(persistence: PersistenceController) { self.persistence = persistence }

    func share(_ objects: [NSManagedObject], to existing: CKShare?) async throws -> CKShare {
        shareCallCount += 1
        if let shareError { throw shareError }
        let share = existing ?? CKShare(recordZoneID: SharingFixtures.zoneID())
        for object in objects { sharesByRoot[object.objectID] = share }
        return share
    }

    func share(forObjectWith objectID: NSManagedObjectID) -> CKShare? { sharesByRoot[objectID] }

    func shares(in store: NSPersistentStore) throws -> [CKShare] {
        var seen = Set<CKRecord.ID>()
        return sharesByRoot
            .filter { $0.key.persistentStore === store }
            .map(\.value)
            .filter { seen.insert($0.recordID).inserted }
    }

    func canUpdateRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool {
        !readOnlyObjectIDs.contains(objectID)
    }

    func recordZoneID(forObjectWith objectID: NSManagedObjectID) -> CKRecordZone.ID? {
        if let override = zoneOverrides[objectID] { return override }
        for (rootID, share) in sharesByRoot {
            guard let root = try? persistence.viewContext.existingObject(with: rootID) else { continue }
            if ObjectGraph.objectIDs(reachableFrom: root).contains(objectID) { return share.recordID.zoneID }
        }
        return nil
    }

    func persistUpdatedShare(_ share: CKShare, in store: NSPersistentStore) async throws -> CKShare {
        if let persistError { throw persistError }
        persistedShares.append((share, store))
        return share
    }

    func purgeObjectsAndRecordsInZone(with zoneID: CKRecordZone.ID, in store: NSPersistentStore) async throws {
        if let purgeError { throw purgeError }
        purgedZones.append((zoneID, store))
        let context = persistence.viewContext
        for (rootID, share) in sharesByRoot where share.recordID.zoneID == zoneID && rootID.persistentStore === store {
            guard let root = try? context.existingObject(with: rootID) else { continue }
            for id in ObjectGraph.objectIDs(reachableFrom: root) {
                context.delete(try context.existingObject(with: id))
            }
            sharesByRoot[rootID] = nil
        }
        try context.save()
    }

    func acceptShareInvitations(from invitations: [any ShareInvitation], into store: NSPersistentStore) async throws {
        acceptCallCount += 1
        if let acceptError { throw acceptError }
        for invitation in invitations { try onAccept?(invitation) }
    }

    // MARK: Test helpers

    /// A household joined from someone else: lives in the shared store with a share owned by `owner`.
    func simulateJoinedHousehold(named name: String, owner: String = "_friend", readOnly: Bool = false,
                                 zoneID: CKRecordZone.ID? = nil) throws -> Space {
        let space = try SharingFixtures.insertSpace(named: name, into: persistence.sharedStore, of: persistence, by: owner)
        sharesByRoot[space.objectID] = CKShare(recordZoneID: zoneID ?? SharingFixtures.zoneID(owner: owner))
        if readOnly { readOnlyObjectIDs.insert(space.objectID) }
        return space
    }
}
