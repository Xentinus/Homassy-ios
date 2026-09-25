import CloudKit
import Testing
@testable import HomassyCore

@MainActor
struct SharingZoneTests {
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

    @Test func findsTheJoinedSpaceForAZone() throws {
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.share.X", ownerName: "_friend")
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs", zoneID: zoneID)
        _ = try cloud.simulateJoinedHousehold(named: "Other")

        #expect(service.space(inZone: ZoneReference(zoneID)) === joined)
        #expect(service.space(inZone: ZoneReference(zoneName: "nope", ownerName: "_x")) == nil)
    }

    @Test func removeLocalCopyPurgesAndToleratesAMissingZone() async throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let id = joined.publicId
        try await service.removeLocalCopy(of: joined)
        #expect(cloud.purgedZones.first?.store === persistence.sharedStore)
        #expect(service.space(withPublicId: id) == nil)

        let second = try cloud.simulateJoinedHousehold(named: "Gone")
        cloud.purgeError = CKError(.zoneNotFound)
        try await service.removeLocalCopy(of: second)             // does not throw
    }

    @Test func removeLocalCopyRejectsOwnedSpaces() async throws {
        let owned = try await service.createHousehold(name: "Mine")
        await #expect(throws: SharingError.notParticipant) { try await service.removeLocalCopy(of: owned) }
    }
}
