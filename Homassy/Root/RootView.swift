import Combine
import CoreData
import HomassyCore
import SwiftUI

/// Routes between the account check, the gate and the main shell.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var exportTarget: Space?
    @State private var inbox = ShareInvitationInbox.shared
    @State private var memberSetupSpace: MemberSetupTarget?
    private let memberSetupSkips = MemberSetupSkips()

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
        // The single owner of the undo toast's VoiceOver announcement (P1-07a): `UndoToastOverlay` is purely
        // visual, since several can be live at once (a tab's and the settings sheet's) while sharing one queue.
        .onChange(of: app.undoQueue.toastTitle) { _, title in
            if let title { AccessibilityNotification.Announcement(title).post() }
        }
        .onChange(of: app.undoQueue.lastError != nil) { _, failed in
            if failed { AccessibilityNotification.Announcement(String(localized: "undo.failed")).post() }
        }
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
                    .environment(attributionTracker(services))
                    .environment(services.syncStatus)
                    .environment(\.memberLookup, memberLookup(services))
                    .onChange(of: app.selection.selectedSpaceID, initial: true) { evaluateMemberSetup() }
                    .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                        .receive(on: RunLoop.main)) { _ in
                        evaluateMemberSetup()       // a joined space's share and permissions arrive with the import
                    }
                    .sheet(item: $memberSetupSpace) { target in
                        if let members = services.members {
                            MemberSetupView(service: members, space: target.space, userRecordName: services.userRecordName) {
                                memberSetupSkips.skip(target.space.publicId)
                            }
                        }
                    }
                    .environment(services)
                    .environment(services.storeDirectory)
                    .expiryNotifications(services.notifications, context: services.context)
                    .storeReminders(services.storeReminders, context: services.context)
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

    private func attributionTracker(_ services: ServiceContainer) -> AttributionTracker {
        #if DEBUG
        if let override = app.attributionOverride { return override }
        #endif
        return services.attribution
    }

    /// Names and colours of the selected space's members, resolved when a flashing card asks.
    private func memberLookup(_ services: ServiceContainer) -> MemberLookup {
        let selection = app.selection
        func space() -> Space? { services.activeSpace(selectedID: selection.selectedSpaceID) }
        return MemberLookup(
            name: { record in
                guard let members = services.members, let space = space() else { return "" }
                return members.displayName(for: record, in: space)
            },
            colorKey: { record in
                guard let members = services.members, let space = space() else { return nil }
                return members.colorKey(for: record, in: space)
            })
    }

    /// First visit to an editable shared household without a named member record: ask for name, photo, colour.
    private func evaluateMemberSetup() {
        guard memberSetupSpace == nil, let services = app.services,
              let members = services.members, let sharing = services.sharing,
              let id = app.selection.selectedSpaceID, !memberSetupSkips.isSkipped(id),
              let space = sharing.space(withPublicId: id),
              members.needsSetup(in: space) else { return }
        memberSetupSpace = MemberSetupTarget(space: space)
    }
}

/// A space waiting for first-visit member setup (`Space` itself is not Identifiable).
private struct MemberSetupTarget: Identifiable {
    let space: Space
    var id: NSManagedObjectID { space.objectID }
}
