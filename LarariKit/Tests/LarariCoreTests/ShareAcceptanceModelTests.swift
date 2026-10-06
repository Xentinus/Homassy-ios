import CloudKit
import Foundation
import Testing
@testable import LarariCore

@MainActor
struct ShareAcceptanceModelTests {
    let persistence: PersistenceController
    let cloud: FakeCloudSharing

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        cloud = FakeCloudSharing(persistence: persistence)
    }

    func makeModel(timeout: Duration = .seconds(2)) -> ShareAcceptanceModel {
        ShareAcceptanceModel(persistence: persistence, cloud: cloud,
                             pollInterval: .milliseconds(10), timeout: timeout)
    }

    @Test func acceptsIntoSharedStoreAndResolvesTheSpace() async throws {
        let cloud = self.cloud
        var joined: Space?
        cloud.onAccept = { invitation in
            joined = try cloud.simulateJoinedHousehold(named: "Theirs", zoneID: invitation.sharedZoneID)
        }
        let model = makeModel()

        await model.accept(FakeShareInvitation())

        #expect(model.state == .accepted(spacePublicId: try #require(joined).publicId))
        #expect(cloud.acceptCallCount == 1)
        #expect(!model.isBusy)
    }

    @Test func waitsForTheImportToDeliverTheSpace() async throws {
        let cloud = self.cloud
        cloud.onAccept = { invitation in
            let zoneID = invitation.sharedZoneID
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                _ = try? cloud.simulateJoinedHousehold(named: "Late", zoneID: zoneID)
            }
        }
        let model = makeModel()

        await model.accept(FakeShareInvitation())

        guard case .accepted = model.state else {
            Issue.record("expected accepted, got \(model.state)")
            return
        }
    }

    @Test func rejectsInvitationForAnotherContainer() async {
        let model = makeModel()
        await model.accept(FakeShareInvitation(containerIdentifier: "iCloud.com.example.other"))
        #expect(model.state == .failed(.wrongContainer))
        #expect(cloud.acceptCallCount == 0)
    }

    @Test func reportsCloudKitFailureAndRetrySucceeds() async throws {
        let cloud = self.cloud
        cloud.acceptError = CKError(.networkUnavailable)
        let model = makeModel()
        let invitation = FakeShareInvitation()

        await model.accept(invitation)
        #expect(model.state == .failed(.cloudKit(code: CKError.Code.networkUnavailable.rawValue)))

        cloud.acceptError = nil
        cloud.onAccept = { invitation in
            _ = try cloud.simulateJoinedHousehold(named: "Theirs", zoneID: invitation.sharedZoneID)
        }
        await model.retry()

        guard case .accepted = model.state else {
            Issue.record("expected accepted after retry, got \(model.state)")
            return
        }
        #expect(cloud.acceptCallCount == 2)
    }

    @Test func timesOutWhenTheSpaceNeverArrives() async {
        let model = makeModel(timeout: .milliseconds(50))
        await model.accept(FakeShareInvitation())
        #expect(model.state == .failed(.timedOut))
    }

    @Test func alreadyJoinedHouseholdSkipsAccepting() async throws {
        let invitation = FakeShareInvitation()
        let joined = try cloud.simulateJoinedHousehold(named: "Theirs", zoneID: invitation.sharedZoneID)
        let model = makeModel()

        await model.accept(invitation)

        #expect(model.state == .accepted(spacePublicId: joined.publicId))
        #expect(cloud.acceptCallCount == 0)
    }

    @Test func resetReturnsToIdle() async {
        let model = makeModel()
        await model.accept(FakeShareInvitation(containerIdentifier: "x"))
        model.reset()
        #expect(model.state == .idle)
    }

    @Test func failureMessagesAreLocalized() {
        #expect(ShareAcceptanceFailure.timedOut.errorDescription?.isEmpty == false)
        #expect(ShareAcceptanceFailure.cloudKit(code: CKError.Code.unknownItem.rawValue).errorDescription
                != ShareAcceptanceFailure.cloudKit(code: 999).errorDescription)
    }
}
