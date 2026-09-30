import Foundation
import HomassyCore
import Observation

/// Opens a destination from outside the view tree: notification taps (P4-06) and Home Screen quick actions (N-02).
/// `MainTabView` applies `pending`; the one-shot requests are consumed by the view they are meant for
/// (`TabNavigationStack`, `InventoryView`, `ShoppingHomeView`).
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// Pop one tab's navigation stack to its root.
    struct PathRequest: Equatable {
        let id = UUID()
        let tab: AppTab
    }

    /// Filter the Shopping home of `spaceID` to `listID` (with `adds`, open the add sheet on it), or with `byStore`
    /// show every list grouped by store (a Live Activity tap, N-04).
    struct ShoppingRequest: Equatable {
        let id = UUID()
        let spaceID: UUID
        let listID: UUID?
        let adds: Bool
        var byStore = false
    }

    var pending: AppDestination?
    var pathRequest: PathRequest?
    var scanRequested = false
    var shoppingRequest: ShoppingRequest?
    /// The region of the store reminder the user tapped (N-04): the shopping Live Activity starts for its chain there.
    var arrivalBranch: ChainBranch?
    /// Bumped on every `open(_:)`, so `SpaceSwitcher` closes its settings sheet even when the tab doesn't change.
    private(set) var openCount = 0

    func open(_ destination: AppDestination) {
        pending = destination
        openCount += 1
    }
}
