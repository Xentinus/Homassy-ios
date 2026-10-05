import HomassyCore
import SwiftUI
import UIKit

/// "Open in New Window" (N-03), the first item of a card's or a list chip's long-press menu, as in Notes, Safari and
/// Mail. It exists only where the system supports several windows (iPad); on the iPhone the menus are unchanged.
struct OpenInNewWindowButton: View {
    let route: WindowRoute
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            #if DEBUG
            UITestHooks.routeWindowRequested = true
            #endif
            openWindow(value: route)
        } label: {
            Label("window.open", systemImage: "macwindow.badge.plus")
        }
        .accessibilityIdentifier("window.open")
    }
}

/// The menu item followed by a divider, or nothing where there is one window only.
struct OpenInNewWindowMenuItems: View {
    let route: WindowRoute
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        if supportsMultipleWindows {
            OpenInNewWindowButton(route: route)
            Divider()
        }
    }
}

/// On iPad, a product card or a list chip can also be dragged to the screen edge to become a window (D3 = B, Notes
/// and Mail). Shopping item cards never get this, because they drag to reorder. Nothing changes on the iPhone.
private struct WindowDragModifier: ViewModifier {
    let route: WindowRoute
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    func body(content: Content) -> some View {
        if supportsMultipleWindows {
            content.onDrag { WindowRouteActivity.itemProvider(for: route) }
        } else {
            content
        }
    }
}

extension View {
    func draggableIntoWindow(_ route: WindowRoute) -> some View {
        modifier(WindowDragModifier(route: route))
    }
}

/// The user activity a dragged card carries (N-03). Dropped at the screen edge, the system creates a scene for it;
/// `targetContentIdentifier` picks the route window group (`handlesExternalEvents`), and `SceneRoot` reads the route
/// back in `onContinueUserActivity`.
enum WindowRouteActivity {
    static func userActivity(for route: WindowRoute) -> NSUserActivity {
        let activity = NSUserActivity(activityType: WindowRoute.activityType)
        activity.targetContentIdentifier = WindowRoute.activityType
        activity.addUserInfoEntries(from: route.userInfo)
        return activity
    }

    static func itemProvider(for route: WindowRoute) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerObject(userActivity(for: route), visibility: .all)
        return provider
    }
}
