import SwiftUI

/// Search tab. Results arrive with the feature tasks; until then it shows the prompt or "no results".
struct SearchView: View {
    @State private var query = ""

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView("search.prompt", systemImage: "magnifyingglass")
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle(AppTab.search.title)
        .searchable(text: $query)
    }
}
