import HomassyCore
import SwiftUI

/// Routes between the account check, the gate and the main shell.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.introduction.shouldShow {
                IntroductionView(model: app.introduction)
                    .transition(.opacity)
            } else {
                accountContent
                    .transition(.opacity)
            }
        }
        .motionAware(Motion.settle, value: app.introduction.shouldShow)
        .environment(app.selection)       // P1-07
        .environment(app.undoQueue)       // P1-08
        .task {
            app.accountGate.startObserving()
            await app.accountGate.refresh()
        }
        .onChange(of: app.accountGate.state, initial: true) { _, state in
            if state == .available { app.bootstrapPersonalSpace() }
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        switch app.accountGate.state {
        case .checking:
            ProgressView("gate.checking")
        case .available:
            if let services = app.services {
                MainTabView()
                    .environment(services)
                    .expiryNotifications(services.notifications, context: services.context)
            } else if app.bootstrapError != nil {
                AccountGateView(state: .couldNotDetermine) { app.bootstrapPersonalSpace() }
            } else {
                ProgressView("gate.checking")
            }
        case let state:
            AccountGateView(state: state) {
                Task { await app.accountGate.refresh() }
            }
        }
    }
}
