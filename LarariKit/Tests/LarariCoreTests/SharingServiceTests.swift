import CloudKit
import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
struct SharingServiceTests {
    let me = "_me"
    let persistence: PersistenceController
    let cloud: FakeCloudSharing
    let spaceStore: SpaceStore
    let service: SharingService
    let personal: Space

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        cloud = FakeCloudSharing(persistence: persistence)
        spaceStore = SpaceStore(persistence: persistence, sharing: cloud)
        service = SharingService(persistence: persistence, spaceStore: spaceStore, cloud: cloud, userRecordName: me)
        personal = try spaceStore.bootstrapPersonalSpace(userRecordName: me)
    }

    // MARK: create

    @Test func createHouseholdCreatesSharedHouseholdInPrivateStore() async throws {
        let space = try await service.createHousehold(name: "  Flat 3  ", ownerDisplayName: "Béla")

        #expect(space.kind == .household)
        #expect(space.name == "Flat 3")
        #expect(space.createdBy == me)
        #expect(spaceStore.store(for: space) === persistence.privateStore)
        #expect(!space.objectID.isTemporaryID)
        #expect(service.role(for: space) == .owner)

        let members = try SharingFixtures.members(of: space, in: persistence)
        #expect(members.count == 1)
        #expect(members.first?.userRecordName == me)
        #expect(members.first?.colorSeed == me)
        #expect(members.first?.displayName == "Béla")
    }

    @Test func createHouseholdConfiguresAndPersistsTheShare() async throws {
        _ = try await service.createHousehold(name: "Flat 3")

        let persisted = try #require(cloud.persistedShares.last)
        #expect(persisted.store === persistence.privateStore)
        #expect(persisted.share[CKShare.SystemFieldKey.title] as? String == "Flat 3")
        #expect(persisted.share.publicPermission == .none)
    }

    @Test func createHouseholdPlacesItAfterExistingHouseholds() async throws {
        let first = try await service.createHousehold(name: "A")
        let second = try await service.createHousehold(name: "B")
        #expect(second.sortOrder > first.sortOrder)
    }

    @Test func createHouseholdRequiresAName() async throws {
        await #expect(throws: ServiceError.nameRequired) {
            _ = try await service.createHousehold(name: "   ")
        }
        #expect(cloud.shareCallCount == 0)
    }

    @Test func createHouseholdKeepsTheSpaceWhenSharingFails() async throws {
        cloud.shareError = CKError(.networkUnavailable)
        var createdId: UUID?
        do {
            _ = try await service.createHousehold(name: "Offline")
            Issue.record("expected createdButNotShared")
        } catch let SharingError.createdButNotShared(spacePublicId) {
            createdId = spacePublicId
        }
        let id = try #require(createdId)
        let space = try #require(try SharingFixtures.fetchSpace(id, in: persistence))
        #expect(service.role(for: space) == .notShared)
        #expect(service.space(withPublicId: space.publicId) === space)
    }

    // MARK: role and permissions

    @Test func roles() async throws {
        let owned = try await service.createHousehold(name: "Mine")
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let imported = try SharingFixtures.insertSpace(named: "Imported", into: persistence.privateStore, of: persistence, by: me)

        #expect(service.role(for: owned) == .owner)
        #expect(service.role(for: joined) == .participant)
        #expect(service.role(for: imported) == .notShared)
        #expect(service.role(for: personal) == .notShared)
    }

    @Test func canEditFollowsParticipantPermission() async throws {
        let owned = try await service.createHousehold(name: "Mine")
        let readWrite = try cloud.simulateJoinedHousehold(named: "RW")
        let readOnly = try cloud.simulateJoinedHousehold(named: "RO", readOnly: true)

        #expect(service.canEdit(personal))
        #expect(service.canEdit(owned))
        #expect(service.canEdit(readWrite))
        #expect(!service.canEdit(readOnly))
    }

    @Test func serviceContainerUsesSharingForEveryServicesPermission() throws {
        let readOnly = try cloud.simulateJoinedHousehold(named: "RO", readOnly: true)
        let services = ServiceContainer(spaceStore: spaceStore, context: persistence.viewContext, userRecordName: me,
                                        notificationCenter: FakeNotificationCenter(), storeSearch: FakeStoreSearch(),
                                        sharing: service)

        #expect(services.sharing === service)
        #expect(!services.storageLocations.canEdit(readOnly))
        #expect(services.storageLocations.canEdit(personal))
    }

    // MARK: leave

    @Test func leavePurgesTheZoneFromTheSharedStore() async throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let id = joined.publicId
        let zoneID = try #require(cloud.share(for: joined)).recordID.zoneID

        try await service.leave(joined)

        #expect(cloud.purgedZones.count == 1)
        #expect(cloud.purgedZones.first?.zoneID == zoneID)
        #expect(cloud.purgedZones.first?.store === persistence.sharedStore)
        #expect(try SharingFixtures.fetchSpace(id, in: persistence) == nil)
    }

    @Test func ownerCannotLeave() async throws {
        let owned = try await service.createHousehold(name: "Mine")
        await #expect(throws: SharingError.notParticipant) { try await service.leave(owned) }
        #expect(cloud.purgedZones.isEmpty)
    }

    // MARK: delete

    @Test func deleteHouseholdPurgesTheZoneFromThePrivateStore() async throws {
        let owned = try await service.createHousehold(name: "Mine")
        let id = owned.publicId

        try await service.deleteHousehold(owned)

        #expect(cloud.purgedZones.first?.store === persistence.privateStore)
        #expect(try SharingFixtures.fetchSpace(id, in: persistence) == nil)
    }

    @Test func participantCannotDeleteHousehold() async throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        await #expect(throws: SharingError.notOwner) { try await service.deleteHousehold(joined) }
    }

    @Test func deletingAnUnsharedHouseholdDeletesLocallyWithoutPurge() async throws {
        let imported = try SharingFixtures.insertSpace(named: "Imported", into: persistence.privateStore, of: persistence, by: me)
        let member = spaceStore.insert(Member.self, in: imported, by: me)
        member.space = imported
        try persistence.viewContext.save()
        let id = imported.publicId

        try await service.deleteHousehold(imported)

        #expect(cloud.purgedZones.isEmpty)
        #expect(try SharingFixtures.fetchSpace(id, in: persistence) == nil)
        #expect(try persistence.viewContext.fetch(NSFetchRequest<Member>(entityName: "Member")).isEmpty)
    }

    @Test func personalSpaceCannotBeDeletedOrShared() async throws {
        await #expect(throws: SharingError.personalSpace) { try await service.deleteHousehold(personal) }
        await #expect(throws: SharingError.personalSpace) { try await service.shareExistingSpace(personal) }
    }

    // MARK: share existing

    @Test func shareExistingSpaceSharesAnImportedHouseholdAndAddsOwnerMember() async throws {
        let imported = try SharingFixtures.insertSpace(named: "Imported", into: persistence.privateStore, of: persistence, by: me)

        let share = try await service.shareExistingSpace(imported)

        #expect(service.role(for: imported) == .owner)
        #expect(share[CKShare.SystemFieldKey.title] as? String == "Imported")
        #expect(share.publicPermission == .none)
        #expect(try SharingFixtures.members(of: imported, in: persistence).map(\.userRecordName) == [me])
    }

    @Test func shareExistingSpaceReturnsTheExistingShare() async throws {
        let owned = try await service.createHousehold(name: "Mine")
        let existing = try #require(service.share(for: owned))
        let calls = cloud.shareCallCount

        let again = try await service.shareExistingSpace(owned)

        #expect(again === existing)
        #expect(cloud.shareCallCount == calls)
    }

    // MARK: helpers

    @Test func suggestedOwnerDisplayNameUsesMostRecentOwnMemberRecord() async throws {
        #expect(service.suggestedOwnerDisplayName() == nil)
        _ = try await service.createHousehold(name: "A", ownerDisplayName: "Béla")
        #expect(service.suggestedOwnerDisplayName() == "Béla")
    }

    @Test func objectsOutsideShareZoneReportsMisplacedObjects() async throws {
        let owned = try await service.createHousehold(name: "Mine")
        #expect(service.objectsOutsideShareZone(in: owned).isEmpty)

        let member = try #require(try SharingFixtures.members(of: owned, in: persistence).first)
        cloud.zoneOverrides[member.objectID] = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        #expect(service.objectsOutsideShareZone(in: owned) == [member.objectID])
    }
}
