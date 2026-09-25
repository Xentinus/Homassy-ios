import HomassyCore
import SwiftUI

/// The main shell: four tabs and search. A tab bar in compact width, a sidebar-capable tab view in regular width.
struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .inventory
    @Environment(ServiceContainer.self) private var services
    @Environment(ArchiveImportRouter.self) private var archiveRouter
    @Environment(BackupReminder.self) private var backupReminder
    @Environment(UndoQueue.self) private var undoQueue
    @Environment(SpaceSelection.self) private var selection

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
            Tab(AppTab.products.title, systemImage: AppTab.products.systemImage, value: AppTab.products) {
                TabNavigationStack(tab: .products) { ProductsView() }
            }
            Tab(AppTab.household.title, systemImage: AppTab.household.systemImage, value: AppTab.household) {
                TabNavigationStack(tab: .household) { HouseholdView() }
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
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    MainTabView().environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    MainTabView().environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
}
#endif
