import CloudKit
import CoreData
import Foundation
import Testing
@testable import LarariCore

/// Stands in for the container calls. Records every call and whether it ran on the main thread.
final class FakeSharingBackend: SharingBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _states: [NSManagedObjectID: ShareState] = [:]
    private var _calls: [String] = []
    private var _mainThreadCalls = 0
    private var _requested: [[NSManagedObjectID]] = []

    var states: [NSManagedObjectID: ShareState] {
        get { lock.withLock { _states } }
        set { lock.withLock { _states = newValue } }
    }
    var calls: [String] { lock.withLock { _calls } }
    var mainThreadCalls: Int { lock.withLock { _mainThreadCalls } }
    var requested: [[NSManagedObjectID]] { lock.withLock { _requested } }

    private func record(_ name: String) {
        let onMain = Thread.isMainThread
        lock.withLock {
            _calls.append(name)
            if onMain { _mainThreadCalls += 1 }
        }
    }

    func states(for objectIDs: [NSManagedObjectID]) async -> [NSManagedObjectID: ShareState] {
        record("states")
        lock.withLock { _requested.append(objectIDs) }
        let known = states
        return known.filter { objectIDs.contains($0.key) }
    }

    func share(_ objectIDs: [NSManagedObjectID], to existing: UncheckedSendable<CKShare>?) async throws -> UncheckedSendable<CKShare> {
        record("share")
        return existing ?? UncheckedSendable(value: CKShare(recordZoneID: SharingFixtures.zoneID()))
    }

    func persistUpdatedShare(_ share: UncheckedSendable<CKShare>, in scope: StoreScope) async throws -> UncheckedSendable<CKShare> {
        record("persist \(scope)")
        return share
    }

    func purgeZone(_ zoneID: CKRecordZone.ID, in scope: StoreScope) async throws { record("purge \(scope)") }

    func acceptShareInvitations(_ metadata: UncheckedSendable<[CKShare.Metadata]>, into scope: StoreScope) async throws {
        record("accept \(scope)")
    }

    func recordZoneID(for objectID: NSManagedObjectID) async -> CKRecordZone.ID? {
        record("zone")
        return nil
    }
}

@MainActor
struct ContainerCloudSharingTests {
    let persistence: PersistenceController
    let backend = FakeSharingBackend()
    let sharing: ContainerCloudSharing
    let owned: Space
    let joined: Space

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        sharing = ContainerCloudSharing(persistence: persistence, backend: backend)
        owned = try SharingFixtures.insertSpace(named: "Mine", into: persistence.privateStore, of: persistence, by: "_me")
        joined = try SharingFixtures.insertSpace(named: "Theirs", into: persistence.sharedStore, of: persistence, by: "_friend")
    }

    @Test func syncLookupsNeverCallTheBackend() {
        _ = sharing.share(for: owned)
        _ = sharing.canUpdateRecord(forManagedObjectWith: joined.objectID)
        _ = sharing.recordZoneID(forObjectWith: owned.objectID)
        _ = try? sharing.shares(in: persistence.privateStore)
        #expect(backend.calls.isEmpty)
    }

    @Test func refreshFillsShareAndPermissionOffTheMainThread() async {
        let share = CKShare(recordZoneID: SharingFixtures.zoneID(owner: "_friend"))
        backend.states = [joined.objectID: ShareState(share: share, canUpdate: false),
                          owned.objectID: ShareState(share: nil, canUpdate: true)]

        await sharing.refreshShares()

        #expect(sharing.share(for: joined) === share)
        #expect(sharing.share(for: owned) == nil)
        #expect(!sharing.canUpdateRecord(forManagedObjectWith: joined.objectID))
        #expect(backend.mainThreadCalls == 0)
        #expect(Set(backend.requested.last ?? []) == [owned.objectID, joined.objectID])
    }

    @Test func aJoinedHouseholdIsReadOnlyUntilThePermissionIsKnown() async {
        #expect(!sharing.canUpdateRecord(forManagedObjectWith: joined.objectID))     // fail closed
        #expect(sharing.canUpdateRecord(forManagedObjectWith: owned.objectID))       // private store: always

        backend.states = [joined.objectID: ShareState(share: CKShare(recordZoneID: SharingFixtures.zoneID()), canUpdate: true)]
        await sharing.refreshShares()
        #expect(sharing.canUpdateRecord(forManagedObjectWith: joined.objectID))
    }

    @Test func deletedSpacesAreNotSentToTheBackend() async throws {
        let gone = owned.objectID
        persistence.viewContext.delete(owned)
        try persistence.viewContext.save()

        await sharing.refreshShares()

        #expect(!(backend.requested.last ?? []).contains(gone))
    }

    @Test func forgetDropsEntries() async {
        backend.states = [joined.objectID: ShareState(share: CKShare(recordZoneID: SharingFixtures.zoneID()), canUpdate: true)]
        await sharing.refreshShares()
        #expect(sharing.share(for: joined) != nil)

        sharing.forget([joined.objectID])

        #expect(sharing.share(for: joined) == nil)
        #expect(!sharing.canUpdateRecord(forManagedObjectWith: joined.objectID))
    }

    @Test func fetchShareAsksTheBackendAndUpdatesTheCache() async {
        let share = CKShare(recordZoneID: SharingFixtures.zoneID())
        backend.states = [owned.objectID: ShareState(share: share, canUpdate: true)]

        let fetched = await sharing.fetchShare(forObjectWith: owned.objectID)

        #expect(fetched === share)
        #expect(sharing.share(for: owned) === share)
    }

    @Test func operationsGoThroughTheBackendWithTheRightStore() async throws {
        let share = CKShare(recordZoneID: SharingFixtures.zoneID())
        _ = try await sharing.share([owned], to: nil)
        _ = try await sharing.persistUpdatedShare(share, in: persistence.privateStore)
        try await sharing.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: persistence.sharedStore)

        #expect(backend.calls.filter { $0 != "states" } == ["share", "persist private", "purge shared"])
        #expect(backend.mainThreadCalls == 0)
    }

    @Test func theRealBackendOnlyKeepsObjectsThatStillExist() throws {
        let gone = owned.objectID
        persistence.viewContext.delete(owned)
        try persistence.viewContext.save()
        let context = persistence.container.newBackgroundContext()

        let kept = ContainerSharingBackend.existing([gone, joined.objectID], in: context)

        #expect(kept == [joined.objectID])
    }
}
