import Foundation
import HomassyCore
import Observation

/// Opens a destination from outside the view tree: notification taps (P4-06), Home Screen quick actions (N-02) and
/// deep links (N-04). It is app-wide; with several iPad windows (N-03) the first active main window takes `pending`
/// (`take()`) and hands the one-shot requests to its own `WindowRouter`, so only that window reacts.
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

    private(set) var pending: AppDestination?
    /// The region of the store reminder the user tapped (N-04): the shopping Live Activity starts for its chain there.
    var arrivalBranch: ChainBranch?

    func open(_ destination: AppDestination) {
        pending = destination
    }

    /// Hands the pending destination to the first window that asks and clears it (N-03).
    func take() -> AppDestination? {
        defer { pending = nil }
        return pending
    }
}

/// One window's routing requests (N-03). `MainTabView` fills them when its window takes an `AppRouter` destination;
/// the views of that window consume them (`TabNavigationStack`, `InventoryView`, `ShoppingHomeView`, `SpaceSwitcher`).
@MainActor
@Observable
final class WindowRouter {
    var pathRequest: AppRouter.PathRequest?
    var scanRequested = false
    /// Show the Inventory grouped by expiry (the Expiring Soon quick action and the expiry notifications, P2-08e).
    var inventoryExpiryRequested = false
    var shoppingRequest: AppRouter.ShoppingRequest?
    /// Bumped on every destination this window opens, so `SpaceSwitcher` closes its settings sheet even when the tab
    /// doesn't change.
    private(set) var openCount = 0

    func didOpen() {
        openCount += 1
    }
}
