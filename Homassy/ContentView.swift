import HomassyCore
import SwiftUI

/// Temporary root. P1-05 replaces it with RootView and deletes this file.
struct ContentView: View {
    var body: some View {
        ProgressView()
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("root.placeholder")
            .accessibilityValue(Text(verbatim: HomassyCore.version))
    }
}

#Preview {
    ContentView()
}
