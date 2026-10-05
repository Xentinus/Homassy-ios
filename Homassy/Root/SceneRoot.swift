import HomassyCore
import HomassyShared
import SwiftUI

/// One window's own state (N-03): its space, its undo queue, its routing requests and its archive import. The tab
/// and the navigation paths were already per window (`@SceneStorage`, P1-07). The space starts from this window's
/// restored one, otherwise from the space last picked in any window.
struct SceneRoot: View {
    /// Nil for a main window; the window's value for a list or product window (`WindowGroup(for: WindowRoute.self)`).
    var route: Binding<WindowRoute?>? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("window.selectedSpaceID") private var storedSpaceID: String?
    @State private var selection: SpaceSelection?
    @State private var undoQueue: UndoQueue?
    @State private var windowRouter = WindowRouter()
    /// A `.homassy` file opened into this window is imported here only, not in every window.
    @State private var archiveRouter = ArchiveImportRouter()

    var body: some View {
        // A ZStack, not a Group: a Group hands its modifiers to each branch, so the task and the URL handler would
        // run again when the window's state appears, and open an archive twice.
        ZStack {
            if let selection, let undoQueue {
                content
                    .environment(selection)
                    .environment(undoQueue)
                    .environment(windowRouter)
                    .environment(archiveRouter)
                    .onChange(of: selection.selectedSpaceID) { _, id in
                        if route == nil { storedSpaceID = id?.uuidString }      // a route window follows its item
                    }
                    .onChange(of: scenePhase) { _, phase in
                        // This window alone going away (Stage Manager, App Exposé) saves its pending changes.
                        if phase == .background { try? undoQueue.commitAll() }
                    }
                    .onDisappear { try? undoQueue.commitAll() }       // window closed: never leave items hidden
            } else {
                Color.clear
            }
        }
        .onAppear(perform: makeWindowState)
        .onOpenURL { url in
            if let link = HomassyDeepLink(url: url) {
                AppRouter.shared.open(AppDestination(link))      // Live Activity and widget taps (N-04, N-05)
            } else {
                archiveRouter.open(url)
            }
        }
        .onContinueUserActivity(WindowRoute.activityType) { activity in
            // A card dragged to the screen edge (D3 = B): the new route window learns what it shows.
            if let route, let value = WindowRoute(userInfo: activity.userInfo ?? [:]) { route.wrappedValue = value }
        }
        #if DEBUG
        .task {
            if route == nil, let url = UITestArchiveHook.fixtureURLIfRequested() { archiveRouter.open(url) }
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if let route, route.wrappedValue == nil {
            ProgressView()          // a window dragged out of a card, waiting for its activity (D3 = B)
        } else {
            RootView(route: shownRoute)
        }
    }

    private var shownRoute: WindowRoute? {
        #if DEBUG
        // A list or product window restored from the previous test launch shows the main shell, so every UI test
        // starts on tabs whichever window the system brings forward.
        if UITestHooks.isActive && !UITestHooks.routeWindowRequested { return nil }
        #endif
        return route?.wrappedValue
    }

    /// Scene storage is readable only once the view is in a window, so the state is made on first appearance.
    private func makeWindowState() {
        guard selection == nil else { return }
        #if DEBUG
        // UI tests start every launch clean, like the tabs and paths (`UITestHooks.ignoresRestoredSceneState`).
        let restored = UITestHooks.ignoresRestoredSceneState ? nil : storedSpaceID.flatMap(UUID.init(uuidString:))
        #else
        let restored = storedSpaceID.flatMap(UUID.init(uuidString:))
        #endif
        selection = SpaceSelection(restoredID: restored)
        undoQueue = app.undoQueues.makeQueue()
    }
}
