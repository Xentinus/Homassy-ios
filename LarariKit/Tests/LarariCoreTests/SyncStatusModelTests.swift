import CloudKit
import Foundation
import Testing
@testable import LarariCore

@MainActor
final class SyncTestClock {
    var date = Date(timeIntervalSince1970: 2_000_000)
    var refreshCount = 0
}

@MainActor
struct SyncStatusModelTests {
    let privateID = "private-store"
    let sharedID = "shared-store"
    let clock = SyncTestClock()

    func makeModel(threshold: Duration = .seconds(60)) -> SyncStatusModel {
        let clock = self.clock
        return SyncStatusModel(privateStoreIdentifier: privateID, persistenceThreshold: threshold, now: { clock.date })
    }

    func event(_ kind: SyncEventSnapshot.Kind = .exporting, store: String? = nil, id: UUID = UUID(),
               ended: Bool = true, succeeded: Bool = true, code: CKError.Code? = nil) -> SyncEventSnapshot {
        SyncEventSnapshot(id: id, storeIdentifier: store ?? privateID, kind: kind, startDate: clock.date,
                          endDate: ended ? clock.date : nil, succeeded: succeeded,
                          failure: code.map { SyncFailureInfo(code: $0.rawValue, isCloudKit: true) })
    }

    @Test func tracksInFlightEvents() {
        let model = makeModel()
        let id = UUID()
        model.handle(event(id: id, ended: false))
        #expect(model.isSyncing)
        model.handle(event(id: id))
        #expect(!model.isSyncing)
    }

    @Test func successRecordsLastSyncExceptSetup() {
        let model = makeModel()
        model.handle(event(.setup))
        #expect(model.lastSuccessfulSync == nil)
        model.handle(event(.importing))
        #expect(model.lastSuccessfulSync == clock.date)
    }

    @Test func singleNetworkFailureIsNotPersistent() {
        let model = makeModel()
        model.handle(event(succeeded: false, code: .networkUnavailable))
        #expect(model.currentError == .network)
        #expect(!model.isPersistent)
        #expect(model.bannerProblem == nil)
    }

    @Test func threeRepeatedFailuresArePersistent() {
        let model = makeModel()
        for _ in 0..<3 { model.handle(event(succeeded: false, code: .networkFailure)) }
        #expect(model.isPersistent)
        #expect(model.bannerProblem == .network)
    }

    @Test func failureLastingPastThresholdIsPersistent() {
        let model = makeModel()
        model.handle(event(succeeded: false, code: .networkFailure))
        clock.date = clock.date.addingTimeInterval(61)
        model.refresh()
        #expect(model.isPersistent)
    }

    @Test func quotaIsPersistentImmediatelyWithOwnerMessage() {
        let model = makeModel()
        model.handle(event(store: privateID, succeeded: false, code: .quotaExceeded))
        #expect(model.currentError == .quotaExceeded(isOwner: true))
        #expect(model.isPersistent)

        let participant = makeModel()
        participant.handle(event(store: sharedID, succeeded: false, code: .quotaExceeded))
        #expect(participant.currentError == .quotaExceeded(isOwner: false))
    }

    @Test func successOfSameStoreAndKindClearsTheProblem() {
        let model = makeModel()
        for _ in 0..<3 { model.handle(event(succeeded: false, code: .networkFailure)) }
        model.handle(event())
        #expect(model.currentError == nil)
        #expect(!model.isPersistent)
    }

    @Test func importSuccessDoesNotClearAnExportProblem() {
        let model = makeModel()
        model.handle(event(.exporting, succeeded: false, code: .quotaExceeded))
        model.handle(event(.importing))
        #expect(model.currentError == .quotaExceeded(isOwner: true))
    }

    @Test func differentProblemRestartsTheCount() {
        let model = makeModel()
        model.handle(event(succeeded: false, code: .networkFailure))
        model.handle(event(succeeded: false, code: .networkFailure))
        model.handle(event(succeeded: false, code: .internalError))
        #expect(model.currentError == .other(code: CKError.Code.internalError.rawValue))
        #expect(!model.isPersistent)
    }

    @Test func notAuthenticatedTriggersAccountRefresh() {
        let model = makeModel()
        let counter = clock
        model.onNotAuthenticated = { counter.refreshCount += 1 }
        model.handle(event(succeeded: false, code: .notAuthenticated))
        #expect(counter.refreshCount == 1)
        #expect(model.isPersistent)
    }

    @Test func zoneGoneCanBeResolved() {
        let model = makeModel()
        model.handle(SyncEventSnapshot(id: UUID(), storeIdentifier: sharedID, kind: .importing, startDate: clock.date,
                                       endDate: clock.date, succeeded: false,
                                       failure: SyncFailureInfo(code: CKError.Code.zoneNotFound.rawValue, isCloudKit: true,
                                                                affectedZones: [ZoneReference(zoneName: "z", ownerName: "_o")])))
        #expect(model.bannerProblem == .zoneGone(ZoneReference(zoneName: "z", ownerName: "_o")))
        model.resolveZoneGone()
        #expect(model.currentError == nil)
    }

    @Test func consumesAStream() async {
        let model = makeModel()
        let (stream, continuation) = AsyncStream.makeStream(of: SyncEventSnapshot.self)
        continuation.yield(event(.importing))
        continuation.yield(event(succeeded: false, code: .quotaExceeded))
        continuation.finish()
        await model.consume(stream)
        #expect(model.lastSuccessfulSync != nil)
        #expect(model.currentError == .quotaExceeded(isOwner: true))
    }

    @Test func becomesPersistentOnItsOwnAfterThreshold() async throws {
        let model = SyncStatusModel(privateStoreIdentifier: privateID, persistenceThreshold: .milliseconds(50))
        model.handle(SyncEventSnapshot(id: UUID(), storeIdentifier: privateID, kind: .exporting, startDate: .now,
                                       endDate: .now, succeeded: false,
                                       failure: SyncFailureInfo(code: CKError.Code.networkFailure.rawValue, isCloudKit: true)))
        #expect(!model.isPersistent)
        // Poll: in a parallel run the main actor is busy, so a fixed sleep is flaky.
        for _ in 0..<100 where !model.isPersistent {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.isPersistent)
    }
}
