@preconcurrency import ActivityKit
import Foundation
import LarariCore
import LarariShared

/// The real `LiveActivityControlling` (N-04): local ActivityKit requests only, no push token, so no entitlement.
/// `Activity` is not Sendable; everything here stays on the main actor.
@MainActor
final class ActivityKitShoppingController: LiveActivityControlling {
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func running() -> [RunningShoppingActivity] {
        Activity<ShoppingActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .map { RunningShoppingActivity(id: $0.id, spaceID: $0.attributes.spaceID, scope: $0.attributes.scope,
                                           content: $0.content.state) }
    }

    func start(_ request: ShoppingActivityRequest) throws -> String {
        let activity = try Activity.request(
            attributes: ShoppingActivityAttributes(spaceID: request.spaceID, scope: request.scope),
            content: ActivityContent(state: request.content, staleDate: request.staleDate,
                                     relevanceScore: request.relevance),
            pushType: nil)
        return activity.id
    }

    func update(id: String, content: ShoppingActivityContent, staleDate: Date?, relevance: Double) async {
        guard let activity = activity(id) else { return }
        await activity.update(ActivityContent(state: content, staleDate: staleDate, relevanceScore: relevance))
    }

    func end(id: String, content: ShoppingActivityContent?, dismissal: ShoppingActivityDismissal) async {
        guard let activity = activity(id) else { return }
        let policy: ActivityUIDismissalPolicy = switch dismissal {
        case .immediate: .immediate
        case .systemDefault: .default
        case let .after(date): .after(date)
        }
        await activity.end(content.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: policy)
    }

    private func activity(_ id: String) -> Activity<ShoppingActivityAttributes>? {
        Activity<ShoppingActivityAttributes>.activities.first { $0.id == id }
    }
}
