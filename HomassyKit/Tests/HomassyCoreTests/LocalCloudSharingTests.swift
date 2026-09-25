import CloudKit
import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
struct LocalCloudSharingTests {
    let me = LocalAccountStatusProvider.userRecordName
    let defaults: UserDefaults
    let persistence: PersistenceController
    let cloud: LocalCloudSharing
    let spaceStore: SpaceStore
    let service: SharingService
    let personal: Space

    init() throws {
        let suite = "LocalCloudSharingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        persistence = try PersistenceController(mode: .inMemory)
        cloud = LocalCloudSharing(persistence: persistence, defaults: defaults)
        spaceStore = SpaceStore(persistence: persistence, sharing: cloud)
        service = SharingService(persistence: persistence, spaceStore: spaceStore, cloud: cloud, userRecordName: me)
        personal = try spaceStore.bootstrapPersonalSpace(userRecordName: me)
    }

    @Test func isNotCloudBacked() {
        #expect(!cloud.isCloudBacked)
        #expect(!service.isCloudBacked)
        #expect(FakeCloudSharing(persistence: persistence).isCloudBacked)   // protocol default
    }

    @Test func createHouseholdIsSharedLocallyWithTheUserAsOwner() async throws {
        let space = try await service.createHousehold(name: "Flat 3", ownerDisplayName: "Béla")

        let share = try #require(service.share(for: space))
        #expect(share.recordID.zoneID == LocalCloudSharing.zoneID(for: space.publicId))
        #expect(share[CKShare.SystemFieldKey.title] as? String == "Flat 3")
        #expect(share.publicPermission == .none)
        #expect(service.role(for: space) == .owner)
        #expect(service.canEdit(space))
        #expect(try cloud.shares(in: persistence.privateStore).count == 1)
        #expect(try cloud.shares(in: persistence.sharedStore).isEmpty)
        #expect(service.objectsOutsideShareZone(in: space).isEmpty)
        #expect(try SharingFixtures.members(of: space, in: persistence).map(\.displayName) == ["Béla"])
    }

    @Test func theShareSurvivesARelaunch() async throws {
        let space = try await service.createHousehold(name: "Flat 3")
        let relaunched = LocalCloudSharing(persistence: persistence, defaults: defaults)
        #expect(relaunched.share(for: space)?.recordID.zoneID == LocalCloudSharing.zoneID(for: space.publicId))
    }

    @Test func thePersonalSpaceIsNeverShared() async throws {
        #expect(cloud.share(for: personal) == nil)
        await #expect(throws: SharingError.personalSpace) { _ = try await cloud.share([personal], to: nil) }
    }

    @Test func acceptingAnInvitationNeedsICloud() async throws {
        await #expect(throws: SharingError.cloudUnavailable) {
            try await cloud.acceptShareInvitations(from: [FakeShareInvitation()], into: persistence.sharedStore)
        }
        #expect(SharingError.cloudUnavailable.errorDescription == "Sharing needs iCloud — available in the released app.")
    }

    @Test func deleteHouseholdPurgesTheSpaceGraph() async throws {
        let space = try await service.createHousehold(name: "Flat 3", ownerDisplayName: "Béla")
        let id = space.publicId

        try await service.deleteHousehold(space)

        #expect(try SharingFixtures.fetchSpace(id, in: persistence) == nil)
        #expect(try persistence.viewContext.fetch(NSFetchRequest<Member>(entityName: "Member")).isEmpty)
        #expect(!(defaults.stringArray(forKey: LocalCloudSharing.sharedSpaceIDsKey) ?? []).contains(id.uuidString))
        #expect(try SharingFixtures.fetchSpace(personal.publicId, in: persistence) != nil)
    }

    @Test func purgingTheLocalZoneIsTheLocalLeave() async throws {
        let space = try await service.createHousehold(name: "Flat 3")
        let id = space.publicId

        try await cloud.purgeObjectsAndRecordsInZone(with: LocalCloudSharing.zoneID(for: id), in: persistence.privateStore)

        #expect(try SharingFixtures.fetchSpace(id, in: persistence) == nil)
        #expect(try cloud.shares(in: persistence.privateStore).isEmpty)
    }

    @Test func theOwnerCannotLeaveALocalHousehold() async throws {
        let space = try await service.createHousehold(name: "Flat 3")
        await #expect(throws: SharingError.notParticipant) { try await service.leave(space) }
    }
}
