#if DEBUG
import Foundation
import LarariCore
import LarariShared
import Observation
import SwiftUI

/// UI tests never start a real Live Activity (N-04): starts and ends are kept in memory, and the probe shows them.
@MainActor
@Observable
final class UITestLiveActivityController: LiveActivityControlling {
    static let shared = UITestLiveActivityController()

    private(set) var activities: [RunningShoppingActivity] = []
    @ObservationIgnored private var counter = 0

    /// "<title>|<remaining>" of the running activity, or "none".
    var summary: String {
        activities.first.map { "\($0.content.title)|\($0.content.remainingCount)" } ?? "none"
    }

    var areActivitiesEnabled: Bool { true }

    func running() -> [RunningShoppingActivity] { activities }

    func start(_ request: ShoppingActivityRequest) throws -> String {
        counter += 1
        let id = "uiTest-\(counter)"
        activities.append(RunningShoppingActivity(id: id, spaceID: request.spaceID, scope: request.scope,
                                                  content: request.content))
        return id
    }

    func update(id: String, content: ShoppingActivityContent, staleDate: Date?, relevance: Double) async {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        let old = activities[index]
        activities[index] = RunningShoppingActivity(id: id, spaceID: old.spaceID, scope: old.scope, content: content)
    }

    func end(id: String, content: ShoppingActivityContent?, dismissal: ShoppingActivityDismissal) async {
        activities.removeAll { $0.id == id }
    }
}

/// Nearly invisible text for `ShoppingActivityUITests`; only under UI tests.
struct UITestLiveActivityProbe: View {
    var body: some View {
        Text(verbatim: UITestLiveActivityController.shared.summary)
            .font(.caption2)
            .opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityIdentifier("uiTest.liveActivity")
    }
}

extension UITestHooks {
    /// `-uiTestNearStore`: the position is the seeded Corner Shop (`UITestSeed`), so the activity starts there.
    static var nearStorePosition: Coordinate? {
        isActive && contains("-uiTestNearStore") ? Coordinate(latitude: 47.4979, longitude: 19.0402) : nil
    }

    /// `-uiTestSeedStoreItems` (needs `-uiTestSeed`): `UITestSeed.populateStoreItems`.
    static var seedsStoreItems: Bool { isActive && contains("-uiTestSeedStoreItems") }
}
#endif
