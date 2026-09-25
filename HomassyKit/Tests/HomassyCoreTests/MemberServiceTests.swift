import CloudKit
import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
struct MemberServiceTests {
    let me = "_me"
    let persistence: PersistenceController
    let cloud: FakeCloudSharing
    let spaceStore: SpaceStore
    let sharing: SharingService
    let service: MemberService
    let personal: Space

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        cloud = FakeCloudSharing(persistence: persistence)
        spaceStore = SpaceStore(persistence: persistence, sharing: cloud)
        sharing = SharingService(persistence: persistence, spaceStore: spaceStore, cloud: cloud, userRecordName: me)
        service = MemberService(persistence: persistence, spaceStore: spaceStore, sharing: sharing, userRecordName: me)
        personal = try spaceStore.bootstrapPersonalSpace(userRecordName: me)
    }

    @Test func ensureCurrentMemberCreatesRecordInTheSharedStore() throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")

        let member = try service.ensureCurrentMember(in: joined, displayName: " Anna ", avatar: nil)

        #expect(member.userRecordName == me)
        #expect(member.colorSeed == me)
        #expect(member.displayName == "Anna")
        #expect(member.space === joined)
        #expect(member.objectID.persistentStore === persistence.sharedStore)
        #expect(member.updatedBy == me)
    }

    @Test func ensureCurrentMemberUpdatesInsteadOfDuplicating() throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        try service.ensureCurrentMember(in: joined, displayName: "Anna", avatar: nil)
        try service.ensureCurrentMember(in: joined, displayName: "Annie", avatar: nil)

        let members = try service.members(in: joined)
        #expect(members.count == 1)
        #expect(members.first?.displayName == "Annie")
    }

    @Test func avatarIsResizedToJPEG() throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let member = try service.ensureCurrentMember(in: joined, displayName: "Anna", avatar: TestImages.jpeg(width: 1600, height: 1200))
        let avatar = try #require(member.avatar)
        #expect(avatar.starts(with: [0xFF, 0xD8]))
    }

    @Test func rejectsEmptyNameReadOnlyAndPersonal() throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let readOnly = try cloud.simulateJoinedHousehold(named: "RO", readOnly: true)

        #expect(throws: ServiceError.nameRequired) { try service.ensureCurrentMember(in: joined, displayName: "  ", avatar: nil) }
        #expect(throws: ServiceError.readOnlySpace) { try service.ensureCurrentMember(in: readOnly, displayName: "Anna", avatar: nil) }
        #expect(throws: SharingError.personalSpace) { try service.ensureCurrentMember(in: personal, displayName: "Anna", avatar: nil) }
    }

    @Test func displayNameFallsBackToNewMember() throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        try service.ensureCurrentMember(in: joined, displayName: "Anna", avatar: nil)
        let blank = spaceStore.insert(Member.self, in: joined, by: "_blank")
        blank.space = joined
        blank.userRecordName = "_blank"
        blank.displayName = ""
        try persistence.viewContext.save()

        #expect(service.displayName(for: me, in: joined) == "Anna")
        #expect(service.displayName(for: "_blank", in: joined) == MemberService.newMemberName)
        #expect(service.displayName(for: "_unknown", in: joined) == MemberService.newMemberName)
        #expect(MemberService.newMemberName == "New member")
    }

    @Test func needsSetupOnlyForEditableSharedHouseholdsWithoutName() async throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let readOnly = try cloud.simulateJoinedHousehold(named: "RO", readOnly: true)
        let owned = try await sharing.createHousehold(name: "Mine", ownerDisplayName: "")

        #expect(service.needsSetup(in: joined))
        #expect(!service.needsSetup(in: readOnly))
        #expect(!service.needsSetup(in: personal))
        #expect(service.needsSetup(in: owned))          // owner created it without a name

        try service.ensureCurrentMember(in: joined, displayName: "Anna", avatar: nil)
        #expect(!service.needsSetup(in: joined))
    }

    @Test func suggestedDisplayNamePrefersOwnNameElsewhere() async throws {
        _ = try await sharing.createHousehold(name: "Mine", ownerDisplayName: "Béla")
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        #expect(service.suggestedDisplayName(in: joined) == "Béla")
    }

    @Test func memberRowsForUnsharedHouseholdListRecords() throws {
        let imported = try SharingFixtures.insertSpace(named: "Imported", into: persistence.privateStore, of: persistence, by: me)
        let other = spaceStore.insert(Member.self, in: imported, by: me)
        other.space = imported
        other.userRecordName = "_x"
        other.colorSeed = "_x"
        other.displayName = "Xénia"
        try persistence.viewContext.save()

        let rows = service.memberRows(in: imported)
        #expect(rows.map(\.displayName) == ["Xénia"])
        #expect(rows.first?.status == .active)
    }

    @Test func memberRowsInLocalModeListTheOwnerRecordAsActive() async throws {
        let suite = "MemberServiceTests.\(UUID().uuidString)"
        let local = LocalCloudSharing(persistence: persistence, defaults: UserDefaults(suiteName: suite)!)
        let localStore = SpaceStore(persistence: persistence, sharing: local)
        let localSharing = SharingService(persistence: persistence, spaceStore: localStore, cloud: local, userRecordName: me)
        let localMembers = MemberService(persistence: persistence, spaceStore: localStore, sharing: localSharing, userRecordName: me)
        let owned = try await localSharing.createHousehold(name: "Mine", ownerDisplayName: "Béla")

        let rows = localMembers.memberRows(in: owned)

        #expect(rows.map(\.displayName) == ["Béla"])
        #expect(rows.first?.status == .active)
        #expect(rows.first?.isCurrentUser == true)
        #expect(!localMembers.needsSetup(in: owned))
        #expect(localMembers.suggestedDisplayName(in: owned) == "Béla")
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    // MARK: Colour pick (plan note from P1-06: Automatic + selectable presets, Mocha included)

    @Test func aPickedColourIsStoredAndResolved() throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let member = try service.ensureCurrentMember(in: joined, displayName: "Anna", avatar: nil, colorKey: "mocha")

        #expect(member.colorKey == "mocha")
        #expect(MemberColor.resolve(key: member.colorKey, seed: me) == MemberColor.mocha)
        #expect(service.memberRows(in: joined).isEmpty == false)

        try service.ensureCurrentMember(in: joined, displayName: "Anna", avatar: nil, colorKey: nil)
        #expect(service.currentMember(in: joined)?.colorKey == nil)
        #expect(MemberColor.resolve(key: nil, seed: me) == MemberColor.preset(for: me))
    }

    @Test func anUnknownColourKeyFallsBackToTheSeed() {
        #expect(MemberColor.resolve(key: "nope", seed: me) == MemberColor.preset(for: me))
    }

    @Test func memberRowsCarryThePickedColour() throws {
        let imported = try SharingFixtures.insertSpace(named: "Imported", into: persistence.privateStore, of: persistence, by: me)
        try service.ensureCurrentMember(in: imported, displayName: "Béla", avatar: nil, colorKey: "mocha")
        #expect(service.memberRows(in: imported).first?.colorKey == "mocha")
    }

    @Test func theLocalOwnerRowIsMarkedOwner() async throws {
        let suite = "MemberServiceTests.owner.\(UUID().uuidString)"
        let local = LocalCloudSharing(persistence: persistence, defaults: UserDefaults(suiteName: suite)!)
        let localStore = SpaceStore(persistence: persistence, sharing: local)
        let localSharing = SharingService(persistence: persistence, spaceStore: localStore, cloud: local, userRecordName: me)
        let localMembers = MemberService(persistence: persistence, spaceStore: localStore, sharing: localSharing, userRecordName: me)
        let owned = try await localSharing.createHousehold(name: "Mine", ownerDisplayName: "Béla")

        #expect(localMembers.memberRows(in: owned).first?.isOwner == true)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }
}
