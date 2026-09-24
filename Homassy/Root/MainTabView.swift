import SwiftUI

/// Main shell shown once iCloud is available. Replaced by the full tab view in P1-07.
struct MainTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("tab.inventory", systemImage: "refrigerator")
                .navigationTitle("tab.inventory")
        }
    }
}

#Preview { MainTabView() }
