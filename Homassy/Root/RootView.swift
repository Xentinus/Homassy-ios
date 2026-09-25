import HomassyCore
import SwiftUI

/// Routes between the account check, the gate and the main shell.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var exportTarget: Space?
    @State private var inbox = ShareInvitationInbox.shared

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
                    .environment(\.requestExport, ExportRequestAction { space in exportTarget = space })
                    .archiveExporting($exportTarget)
                    .shareAcceptanceOverlay(app.shareAcceptance)
                    .onChange(of: inbox.pending.count, initial: true) { startNextInvitation() }
                    .onChange(of: app.shareAcceptance.state) { _, state in
                        if case let .accepted(id) = state {
                            app.selection.selectedSpaceID = id      // P5-03 then shows member setup for it
                            app.shareAcceptance.reset()
                            startNextInvitation()
                        }
                    }
                    .environment(app.shareAcceptance)
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

    /// Invitations wait in the inbox until the services exist, then are accepted one at a time.
    private func startNextInvitation() {
        guard app.shareAcceptance.state == .idle, let next = inbox.takeNext() else { return }
        Task { await app.shareAcceptance.accept(next) }
    }
}
