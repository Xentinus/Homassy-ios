import CloudKit
import Testing
@testable import LarariCore

@MainActor
struct NewHouseholdModelTests {
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

    @Test func cannotCreateWithoutName() {
        let model = NewHouseholdModel(service: service)
        #expect(!model.canCreate)
        model.name = "  "
        #expect(!model.canCreate)
        model.name = "Home"
        #expect(model.canCreate)
    }

    @Test func createSetsCreatedSpace() async {
        let model = NewHouseholdModel(service: service)
        model.name = "Home"
        model.ownerDisplayName = "Béla"
        await model.create()
        #expect(model.createdSpace?.name == "Home")
        #expect(model.errorMessage == nil)
        #expect(!model.isCreating)
    }

    @Test func shareFailureStillReturnsSpaceWithMessage() async {
        cloud.shareError = CKError(.networkUnavailable)
        let model = NewHouseholdModel(service: service)
        model.name = "Home"
        await model.create()
        #expect(model.createdSpace?.name == "Home")
        #expect(model.errorMessage == SharingError.createdButNotShared(spacePublicId: model.createdSpace!.publicId).errorDescription)
    }

    @Test func prefillsOwnerNameFromEarlierHousehold() async throws {
        _ = try await service.createHousehold(name: "First", ownerDisplayName: "Béla")
        #expect(NewHouseholdModel(service: service).ownerDisplayName == "Béla")
    }
}
