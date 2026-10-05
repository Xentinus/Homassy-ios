import HomassyCore
import SwiftUI

/// The main shell (P1-07a): Inventory, Shopping and the Search tab. A tab bar in compact width, a sidebar-capable
/// tab view in regular width. The space's settings open from the space menu, not from a tab. The selected tab is
/// per window (scene storage); the import sheet is presented by `RootView` (`archiveImportPresentation`, N-03).
struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .inventory
    @Environment(ServiceContainer.self) private var services
    @Environment(BackupReminder.self) private var backupReminder
    @Environment(SpaceSelection.self) private var selection
    @Environment(WindowRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var appRouter = AppRouter.shared

    @ViewBuilder
    private var inventoryRoot: some View {
        #if DEBUG
        if UITestHooks.contains("-uiTestUndoDemo") {
            UITestUndoDemoView()
        } else {
            InventoryView()
        }
        #else
        InventoryView()
        #endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.inventory.title, systemImage: AppTab.inventory.systemImage, value: AppTab.inventory) {
                TabNavigationStack(tab: .inventory) { inventoryRoot }
            }
            Tab(AppTab.shopping.title, systemImage: AppTab.shopping.systemImage, value: AppTab.shopping) {
                TabNavigationStack(tab: .shopping) { ShoppingRootView() }
            }
            Tab(AppTab.search.title, systemImage: AppTab.search.systemImage, value: AppTab.search, role: .search) {
                TabNavigationStack(tab: .search) { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task { backupReminder.recordFirstUseIfNeeded() }
        .onChange(of: appRouter.pending, initial: true) { takeDestination() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { takeDestination() }      // a cold start from a tap becomes active after the tap
        }
        #if DEBUG
        .task {
            if UITestHooks.ignoresRestoredSceneState { selectedTab = .inventory }
            UITestHooks.runQuickActionIfRequested(services: services)       // after the reset, never before
        }
        .overlay(alignment: .topLeading) {
            if UITestHooks.isActive { UITestLiveActivityProbe() }
        }
        #endif
    }

    /// A notification tap, quick action or deep link opens in one window only: the first active main window takes
    /// it (N-03).
    private func takeDestination() {
        guard scenePhase == .active, appRouter.pending != nil, let destination = appRouter.take() else { return }
        apply(services.validated(destination))
    }

    /// Selects the space and the tab, and hands the stack, filter and sheet requests to the views that own them.
    private func apply(_ destination: AppDestination) {
        router.didOpen()
        switch destination {
        case .inventory(let space):
            if let space { selection.selectedSpaceID = space }
            selectedTab = .inventory
            router.pathRequest = AppRouter.PathRequest(tab: .inventory)
        case .inventoryExpiring(let space):
            if let space { selection.selectedSpaceID = space }
            selectedTab = .inventory
            router.pathRequest = AppRouter.PathRequest(tab: .inventory)
            router.inventoryExpiryRequested = true
        case .shoppingByStore(let space):
            selection.selectedSpaceID = space
            selectedTab = .shopping
            router.pathRequest = AppRouter.PathRequest(tab: .shopping)
            router.shoppingRequest = AppRouter.ShoppingRequest(spaceID: space, listID: nil, adds: false, byStore: true)
        case .shopping(let space):
            if let space { selection.selectedSpaceID = space }
            selectedTab = .shopping
            router.pathRequest = AppRouter.PathRequest(tab: .shopping)
        case let .shoppingList(space, list):
            selection.selectedSpaceID = space
            selectedTab = .shopping
            router.pathRequest = AppRouter.PathRequest(tab: .shopping)
            router.shoppingRequest = AppRouter.ShoppingRequest(spaceID: space, listID: list, adds: false)
        case let .addToShoppingList(space, list):
            selection.selectedSpaceID = space
            selectedTab = .shopping
            router.pathRequest = AppRouter.PathRequest(tab: .shopping)
            router.shoppingRequest = AppRouter.ShoppingRequest(spaceID: space, listID: list, adds: true)
        case .scanBarcode:
            selectedTab = .inventory
            router.pathRequest = AppRouter.PathRequest(tab: .inventory)
            router.scanRequested = true
        }
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    MainTabView().environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.syncStatus)
        .environment(model.services!.storeDirectory)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
        .environment(WindowRouter())
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    MainTabView().environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.syncStatus)
        .environment(model.services!.storeDirectory)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
        .environment(WindowRouter())
}
#endif
