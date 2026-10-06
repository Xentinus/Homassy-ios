import Foundation
import Testing
@testable import LarariCore

@MainActor
struct MemberSetupModelTests {
    let persistence: PersistenceController
    let cloud: FakeCloudSharing
    let sharing: SharingService
    let service: MemberService

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        cloud = FakeCloudSharing(persistence: persistence)
        let spaceStore = SpaceStore(persistence: persistence, sharing: cloud)
        sharing = SharingService(persistence: persistence, spaceStore: spaceStore, cloud: cloud, userRecordName: "_me")
        service = MemberService(persistence: persistence, spaceStore: spaceStore, sharing: sharing, userRecordName: "_me")
        _ = try spaceStore.bootstrapPersonalSpace(userRecordName: "_me")
    }

    @Test func prefillsAndSaves() async throws {
        _ = try await sharing.createHousehold(name: "Mine", ownerDisplayName: "Béla")
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let model = MemberSetupModel(service: service, space: joined)

        #expect(model.name == "Béla")
        #expect(model.spaceName == "Theirs")
        model.name = "Bélus"
        model.save()

        #expect(model.didSave)
        #expect(model.errorMessage == nil)
        #expect(service.displayName(for: "_me", in: joined) == "Bélus")
    }

    @Test func emptyNameCannotSave() throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let model = MemberSetupModel(service: service, space: joined)
        model.name = " "
        #expect(!model.canSave)
    }

    @Test func readOnlyShowsError() throws {
        let readOnly = try cloud.simulateJoinedHousehold(named: "RO", readOnly: true)
        let model = MemberSetupModel(service: service, space: readOnly)
        model.name = "Anna"
        model.save()
        #expect(!model.didSave)
        #expect(model.errorMessage == ServiceError.readOnlySpace.errorDescription)
    }

    @Test func skipsArePersistedPerSpace() {
        let defaults = UserDefaults(suiteName: "MemberSetupSkips-\(UUID().uuidString)")!
        let a = UUID(), b = UUID()
        MemberSetupSkips(defaults: defaults).skip(a)
        let reloaded = MemberSetupSkips(defaults: defaults)
        #expect(reloaded.isSkipped(a))
        #expect(!reloaded.isSkipped(b))
    }

    @Test func savesThePickedColourAndPrefillsIt() throws {
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs")
        let model = MemberSetupModel(service: service, space: joined)
        #expect(model.colorKey == nil)          // Automatic
        model.name = "Anna"
        model.colorKey = "mocha"
        model.save()

        #expect(MemberSetupModel(service: service, space: joined).colorKey == "mocha")
    }
}
