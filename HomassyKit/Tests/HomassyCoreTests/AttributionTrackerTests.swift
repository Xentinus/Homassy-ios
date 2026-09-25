import Foundation
import Testing
@testable import HomassyCore

@MainActor
final class NowBox {
    var date = Date(timeIntervalSince1970: 1_000_000)
}

@MainActor
struct AttributionTrackerTests {
    let change = ForeignChange(publicId: UUID(), entityName: "ShoppingListItem", userRecordName: "_anna")

    @Test func defaultWindowMatchesTheWebFlash() {
        #expect(AttributionTracker.defaultWindow == .milliseconds(1500))
    }

    @Test func recordsForTheWindow() {
        let clock = NowBox()
        let tracker = AttributionTracker(now: { clock.date })
        tracker.record([change])

        #expect(tracker.attribution(for: change.publicId) ==
                Attribution(userRecordName: "_anna", until: clock.date.addingTimeInterval(1.5)))

        clock.date = clock.date.addingTimeInterval(1.6)
        #expect(tracker.attribution(for: change.publicId) == nil)
        tracker.pruneExpired()
        #expect(tracker.recentlyChangedByOthers.isEmpty)
    }

    @Test func aNewChangeExtendsTheWindow() {
        let clock = NowBox()
        let tracker = AttributionTracker(now: { clock.date })
        tracker.record([change])
        clock.date = clock.date.addingTimeInterval(1)
        tracker.record([ForeignChange(publicId: change.publicId, entityName: change.entityName, userRecordName: "_bea")])

        #expect(tracker.attribution(for: change.publicId)?.userRecordName == "_bea")
        #expect(tracker.attribution(for: change.publicId)?.until == clock.date.addingTimeInterval(1.5))
    }

    @Test func expiresOnItsOwn() async throws {
        let tracker = AttributionTracker(window: .milliseconds(50))
        tracker.record([change])
        #expect(!tracker.recentlyChangedByOthers.isEmpty)
        // Poll: in a parallel run the main actor is busy, so a fixed sleep is flaky.
        for _ in 0..<100 where !tracker.recentlyChangedByOthers.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(tracker.recentlyChangedByOthers.isEmpty)
    }

    @Test func emptyRecordChangesNothing() {
        let tracker = AttributionTracker()
        tracker.record([])
        #expect(tracker.recentlyChangedByOthers.isEmpty)
    }

    @Test func aCardFlashesForAnyOfItsRecords() {
        let clock = NowBox()
        let tracker = AttributionTracker(now: { clock.date })
        let item = UUID()
        tracker.record([ForeignChange(publicId: item, entityName: "InventoryItem", userRecordName: "_bea")])

        #expect(tracker.attribution(forAnyOf: [UUID(), item])?.userRecordName == "_bea")
        #expect(tracker.attribution(forAnyOf: [UUID()]) == nil)
    }

    @Test func theLatestChangeWinsAcrossACardsRecords() {
        let clock = NowBox()
        let tracker = AttributionTracker(now: { clock.date })
        let product = UUID(), item = UUID()
        tracker.record([ForeignChange(publicId: product, entityName: "Product", userRecordName: "_anna")])
        clock.date = clock.date.addingTimeInterval(0.5)
        tracker.record([ForeignChange(publicId: item, entityName: "InventoryItem", userRecordName: "_bea")])

        #expect(tracker.attribution(forAnyOf: [product, item])?.userRecordName == "_bea")
    }
}

