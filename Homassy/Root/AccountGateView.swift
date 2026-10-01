import HomassyCore
import SwiftUI
import UIKit

/// Explains why Homassy cannot be used right now. There is no way past it other than fixing iCloud.
struct AccountGateView: View {
    let state: AccountState
    let retry: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Scrolls once the largest text sizes no longer fit; otherwise centred as before (X-04).
        GeometryReader { proxy in
            ScrollView {
                content.frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accountGate")
    }

    private var content: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if offersRetry {
                Button("gate.retry", action: retry)
                    .buttonStyle(.borderedProminent)
            }
            if offersSettings {
                Button("gate.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var title: LocalizedStringKey {
        switch state {
        case .noAccount, .restricted: "gate.required.title"
        case .temporarilyUnavailable: "gate.unavailable.title"
        case .checking, .available, .couldNotDetermine: "gate.unknown.title"
        }
    }

    private var message: LocalizedStringKey {
        switch state {
        case .noAccount: "gate.noAccount.message"
        case .restricted: "gate.restricted.message"
        case .temporarilyUnavailable: "gate.unavailable.message"
        case .checking, .available, .couldNotDetermine: "gate.unknown.message"
        }
    }

    private var symbol: String {
        switch state {
        case .temporarilyUnavailable: "icloud.slash"
        case .noAccount, .restricted: "person.crop.circle.badge.exclamationmark"
        case .checking, .available, .couldNotDetermine: "exclamationmark.icloud"
        }
    }

    private var offersRetry: Bool { state == .temporarilyUnavailable || state == .couldNotDetermine }
    private var offersSettings: Bool { state == .noAccount || state == .restricted }
}

#Preview("No account") { AccountGateView(state: .noAccount) {} }
#Preview("Restricted") { AccountGateView(state: .restricted) {} }
#Preview("Unavailable") { AccountGateView(state: .temporarilyUnavailable) {} }
#Preview("Unknown") { AccountGateView(state: .couldNotDetermine) {} }
#Preview("Landscape", traits: .landscapeLeft) { AccountGateView(state: .noAccount) {} }
