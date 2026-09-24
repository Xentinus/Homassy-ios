import SwiftUI

/// The main shell: four tabs and search. A tab bar in compact width, a sidebar-capable tab view in regular width.
struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .inventory

    @ViewBuilder
    private var inventoryRoot: some View {
        #if DEBUG
        if UITestHooks.contains("-uiTestUndoDemo") {
            UITestUndoDemoView()
        } else {
            TabPlaceholderView(tab: .inventory)
        }
        #else
        TabPlaceholderView(tab: .inventory)
        #endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.inventory.title, systemImage: AppTab.inventory.systemImage, value: AppTab.inventory) {
                TabNavigationStack(tab: .inventory) { inventoryRoot }
            }
            Tab(AppTab.shopping.title, systemImage: AppTab.shopping.systemImage, value: AppTab.shopping) {
                TabNavigationStack(tab: .shopping) { TabPlaceholderView(tab: .shopping) }
            }
            Tab(AppTab.products.title, systemImage: AppTab.products.systemImage, value: AppTab.products) {
                TabNavigationStack(tab: .products) { TabPlaceholderView(tab: .products) }
            }
            Tab(AppTab.household.title, systemImage: AppTab.household.systemImage, value: AppTab.household) {
                TabNavigationStack(tab: .household) { TabPlaceholderView(tab: .household) }
            }
            Tab(AppTab.search.title, systemImage: AppTab.search.systemImage, value: AppTab.search, role: .search) {
                TabNavigationStack(tab: .search) { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    MainTabView().environment(model).environment(model.selection).environment(model.undoQueue)
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    MainTabView().environment(model).environment(model.selection).environment(model.undoQueue)
}
#endif
