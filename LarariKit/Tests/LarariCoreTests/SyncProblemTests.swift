import CloudKit
import Foundation
import Testing
@testable import LarariCore

struct SyncProblemTests {
    let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.share.ABC", ownerName: "_owner")

    func info(_ code: CKError.Code, partial: [CKError.Code] = [], zones: [ZoneReference] = []) -> SyncFailureInfo {
        SyncFailureInfo(code: code.rawValue, isCloudKit: true, partialCodes: partial.map(\.rawValue), affectedZones: zones)
    }

    @Test func quotaDependsOnStore() {
        #expect(SyncProblem.classify(info(.quotaExceeded), isPrivateStore: true) == .quotaExceeded(isOwner: true))
        #expect(SyncProblem.classify(info(.quotaExceeded), isPrivateStore: false) == .quotaExceeded(isOwner: false))
    }

    @Test func networkCodes() {
        for code: CKError.Code in [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy] {
            #expect(SyncProblem.classify(info(code), isPrivateStore: true) == .network)
        }
    }

    @Test func authenticationCodes() {
        #expect(SyncProblem.classify(info(.notAuthenticated), isPrivateStore: true) == .notAuthenticated)
        #expect(SyncProblem.classify(info(.accountTemporarilyUnavailable), isPrivateStore: false) == .notAuthenticated)
    }

    @Test func zoneGoneOnlyForSharedStore() {
        let zone = ZoneReference(zoneID)
        #expect(SyncProblem.classify(info(.zoneNotFound, zones: [zone]), isPrivateStore: false) == .zoneGone(zone))
        #expect(SyncProblem.classify(info(.userDeletedZone), isPrivateStore: false) == .zoneGone(nil))
        #expect(SyncProblem.classify(info(.zoneNotFound), isPrivateStore: true) == .other(code: CKError.Code.zoneNotFound.rawValue))
    }

    @Test func partialFailureUsesHighestPriorityChild() {
        let mixed = info(.partialFailure, partial: [.networkFailure, .quotaExceeded, .zoneNotFound])
        #expect(SyncProblem.classify(mixed, isPrivateStore: false) == .quotaExceeded(isOwner: false))
        #expect(SyncProblem.classify(info(.partialFailure, partial: [.networkFailure]), isPrivateStore: true) == .network)
        #expect(SyncProblem.classify(info(.partialFailure), isPrivateStore: true) == .other(code: CKError.Code.partialFailure.rawValue))
    }

    @Test func nonCloudKitErrorIsOther() {
        let failure = SyncFailureInfo(code: 134_400, isCloudKit: false)
        #expect(SyncProblem.classify(failure, isPrivateStore: true) == .other(code: 134_400))
    }

    @Test func failureInfoReadsPartialErrorsAndZones() {
        let error = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [zoneID: CKError(.zoneNotFound)]])
        let failure = SyncFailureInfo(error: error)
        #expect(failure.isCloudKit)
        #expect(failure.code == CKError.Code.partialFailure.rawValue)
        #expect(failure.partialCodes == [CKError.Code.zoneNotFound.rawValue])
        #expect(failure.affectedZones == [ZoneReference(zoneID)])
    }

    @Test func failureInfoUnwrapsUnderlyingCloudKitError() {
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400,
                              userInfo: [NSUnderlyingErrorKey: CKError(.quotaExceeded) as NSError])
        let failure = SyncFailureInfo(error: wrapped)
        #expect(failure.isCloudKit)
        #expect(failure.code == CKError.Code.quotaExceeded.rawValue)
    }

    @Test func healingAndMessages() {
        #expect(SyncProblem.network.healsOnItsOwn)
        #expect(SyncProblem.other(code: 1).healsOnItsOwn)
        #expect(!SyncProblem.quotaExceeded(isOwner: true).healsOnItsOwn)
        #expect(!SyncProblem.notAuthenticated.healsOnItsOwn)
        #expect(!SyncProblem.zoneGone(nil).healsOnItsOwn)

        #expect(SyncProblem.quotaExceeded(isOwner: true).message != SyncProblem.quotaExceeded(isOwner: false).message)
        #expect(SyncProblem.quotaExceeded(isOwner: false).message == "This household isn't syncing because its owner's iCloud storage is full.")
        #expect(SyncProblem.other(code: 42).message.contains("42"))
    }
}
