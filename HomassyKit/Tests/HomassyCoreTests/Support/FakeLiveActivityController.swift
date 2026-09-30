import Foundation
import HomassyShared
@testable import HomassyCore

/// Records what the coordinator asks of ActivityKit. `dismissByUser(_:)` plays a Lock Screen swipe.
@MainActor
final class FakeLiveActivityController: LiveActivityControlling {
    struct Ended: Equatable { let id: String; let content: ShoppingActivityContent?; let dismissal: ShoppingActivityDismissal }

    var areActivitiesEnabled = true
    var refusesStart = false
    /// Keeps an ending activity listed for a while, as ActivityKit does until the end call returns.
    var endDelay: Duration?
    private(set) var activities: [RunningShoppingActivity] = []
    private(set) var started: [ShoppingActivityRequest] = []
    private(set) var updates: [ShoppingActivityContent] = []
    private(set) var updateStaleDates: [Date?] = []
    private(set) var ended: [Ended] = []
    private var counter = 0

    func running() -> [RunningShoppingActivity] { activities }

    func start(_ request: ShoppingActivityRequest) throws -> String {
        if refusesStart { throw ShoppingActivityError.unavailable }
        counter += 1
        let id = "activity-\(counter)"
        started.append(request)
        activities.append(RunningShoppingActivity(id: id, spaceID: request.spaceID, scope: request.scope,
                                                  content: request.content))
        return id
    }

    func update(id: String, content: ShoppingActivityContent, staleDate: Date?, relevance: Double) async {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        updates.append(content)
        updateStaleDates.append(staleDate)
        let old = activities[index]
        activities[index] = RunningShoppingActivity(id: id, spaceID: old.spaceID, scope: old.scope, content: content)
    }

    func end(id: String, content: ShoppingActivityContent?, dismissal: ShoppingActivityDismissal) async {
        ended.append(Ended(id: id, content: content, dismissal: dismissal))
        if let endDelay { try? await Task.sleep(for: endDelay) }
        activities.removeAll { $0.id == id }
    }

    func dismissByUser(_ id: String) { activities.removeAll { $0.id == id } }

    /// An activity an earlier process left running.
    func seed(_ activity: RunningShoppingActivity) { activities.append(activity) }

    var latest: ShoppingActivityContent? { activities.first?.content }
}
