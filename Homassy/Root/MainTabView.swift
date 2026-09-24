import SwiftUI

/// The main shell: four tabs and search. A tab bar in compact width, a sidebar-capable tab view in regular width.
struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .inventory

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.inventory.title, systemImage: AppTab.inventory.systemImage, value: AppTab.inventory) {
                TabNavigationStack(tab: .inventory) { TabPlaceholderView(tab: .inventory) }
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
    MainTabView().environment(model).environment(model.selection)
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    MainTabView().environment(model).environment(model.selection)
}
#endif
