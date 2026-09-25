import CloudKit
import CoreData
import Testing
@testable import HomassyCore

@MainActor
struct SharingControllerHookTests {
    let persistence: PersistenceController
    let cloud: FakeCloudSharing
    let service: SharingService

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        cloud = FakeCloudSharing(persistence: persistence)
        let spaceStore = SpaceStore(persistence: persistence, sharing: cloud)
        service = SharingService(persistence: persistence, spaceStore: spaceStore, cloud: cloud, userRecordName: "_me")
        _ = try spaceStore.bootstrapPersonalSpace(userRecordName: "_me")
    }

    @Test func savedShareIsPersistedInTheSpacesStore() async throws {
        let owned = try await service.createHousehold(name: "Mine")
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")

        try await service.saveUpdatedShare(try #require(service.share(for: owned)), for: owned)
        try await service.saveUpdatedShare(try #require(service.share(for: joined)), for: joined)

        #expect(cloud.persistedShares.suffix(2).map { $0.store === persistence.privateStore } == [true, false])
        #expect(cloud.persistedShares.last?.store === persistence.sharedStore)
    }

    @Test func participantStoppingPurgesTheLocalCopy() async throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let zoneID = try #require(service.share(for: joined)).recordID.zoneID
        let id = joined.publicId

        try await service.sharingStopped(for: joined, zoneID: zoneID, wasOwner: false)

        #expect(cloud.purgedZones.first?.store === persistence.sharedStore)
        #expect(service.space(withPublicId: id) == nil)
    }

    @Test func participantStoppingAfterContainerAlreadyRemovedItDoesNothing() async throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let zoneID = try #require(service.share(for: joined)).recordID.zoneID
        persistence.viewContext.delete(joined)
        try persistence.viewContext.save()

        try await service.sharingStopped(for: joined, zoneID: zoneID, wasOwner: false)

        #expect(cloud.purgedZones.isEmpty)
    }

    @Test func ownerStoppingKeepsTheData() async throws {
        let owned = try await service.createHousehold(name: "Mine")
        let zoneID = try #require(service.share(for: owned)).recordID.zoneID
        cloud.sharesByRoot[owned.objectID] = nil          // the container forgets the deleted share

        try await service.sharingStopped(for: owned, zoneID: zoneID, wasOwner: true)

        #expect(cloud.purgedZones.isEmpty)
        #expect(service.space(withPublicId: owned.publicId) === owned)
        #expect(service.role(for: owned) == .notShared)
    }

    @Test func zoneAlreadyGoneIsNotAnError() async throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let zoneID = try #require(service.share(for: joined)).recordID.zoneID
        cloud.purgeError = CKError(.zoneNotFound)

        try await service.sharingStopped(for: joined, zoneID: zoneID, wasOwner: false)
    }
}
