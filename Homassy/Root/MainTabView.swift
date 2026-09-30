import HomassyCore
import SwiftUI

/// The main shell (P1-07a): Inventory, Shopping and the Search tab. A tab bar in compact width, a sidebar-capable
/// tab view in regular width. The space's settings open from the space menu, not from a tab.
struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .inventory
    @Environment(ServiceContainer.self) private var services
    @Environment(ArchiveImportRouter.self) private var archiveRouter
    @Environment(BackupReminder.self) private var backupReminder
    @Environment(UndoQueue.self) private var undoQueue
    @Environment(SpaceSelection.self) private var selection
    @State private var router = AppRouter.shared

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
        .sheet(item: Bindable(archiveRouter).pending) { pending in
            if let archive = services.archive {
                ImportFlowView(url: pending.url, archive: archive, undoQueue: undoQueue) { space in
                    selection.select(space)
                }
            }
        }
        .alert(Text("archive.import.failed.title"),
               isPresented: Binding(get: { archiveRouter.errorMessage != nil },
                                    set: { if !$0 { archiveRouter.errorMessage = nil } })) {
            Button("archive.ok", role: .cancel) {}
        } message: {
            Text(verbatim: archiveRouter.errorMessage ?? "")
        }
        .task { backupReminder.recordFirstUseIfNeeded() }
        .onChange(of: router.pending, initial: true) { _, destination in
            guard let destination else { return }
            router.pending = nil
            apply(services.validated(destination))
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

    /// Selects the space and the tab, and hands the stack, filter and sheet requests to the views that own them.
    private func apply(_ destination: AppDestination) {
        switch destination {
        case .inventory(let space):
            if let space { selection.selectedSpaceID = space }
            selectedTab = .inventory
            router.pathRequest = AppRouter.PathRequest(tab: .inventory)
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
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    MainTabView().environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.syncStatus)
        .environment(model.services!.storeDirectory)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
}
#endif
