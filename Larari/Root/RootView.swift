import Combine
import CoreData
import LarariCore
import SwiftUI

/// Routes between the account check, the gate and the main shell, or a list or product window (N-03). The space
/// and the undo queue are this window's (`SceneRoot`). App-wide one-shot events (share invitations, first-visit
/// member setup) are taken by exactly one window.
struct RootView: View {
    /// Set for a list or product window (N-03); nil for a main window with tabs.
    var route: WindowRoute? = nil

    @Environment(AppModel.self) private var app
    @Environment(SpaceSelection.self) private var selection
    @Environment(UndoQueue.self) private var undoQueue
    @Environment(\.scenePhase) private var scenePhase
    @State private var exportTarget: Space?
    @State private var inbox = ShareInvitationInbox.shared
    @State private var memberSetupSpace: MemberSetupTarget?
    /// Identifies this window when it claims a share invitation.
    @State private var windowID = UUID()
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
        // The single owner of the undo toast's VoiceOver announcement (P1-07a): `UndoToastOverlay` is purely
        // visual, since several can be live at once (a tab's and the settings sheet's) while sharing one queue.
        // Each window announces its own queue only (N-03).
        .onChange(of: undoQueue.toastTitle) { _, title in
            if let title { AccessibilityNotification.Announcement(title).post() }
        }
        .onChange(of: undoQueue.lastError != nil) { _, failed in
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
                windowContent
                    .archiveImportPresentation()
                    .environment(\.requestExport, ExportRequestAction { space in exportTarget = space })
                    .archiveExporting($exportTarget)
                    .shareAcceptanceOverlay(app.shareAcceptance, isOwner: ownsInvitation)
                    .onChange(of: inbox.pending.count, initial: true) { startNextInvitation() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { startNextInvitation() }
                    }
                    .onChange(of: app.shareAcceptance.state) { _, state in
                        guard ownsInvitation, case let .accepted(id) = state else { return }
                        selection.selectedSpaceID = id      // P5-03 then shows member setup for it
                        inbox.owner = nil
                        app.shareAcceptance.reset()
                        startNextInvitation()
                    }
                    .onDisappear {
                        // A closed window hands its claims back: the invitation, and the member setup it was asking.
                        if inbox.owner == windowID { inbox.owner = nil }
                        if memberSetupSpace != nil { app.memberSetupSpaceID = nil }
                    }
                    .environment(app.shareAcceptance)
                    .environment(attributionTracker(services))
                    .environment(services.syncStatus)
                    .environment(\.memberLookup, memberLookup(services))
                    .onChange(of: selection.selectedSpaceID, initial: true) { evaluateMemberSetup() }
                    .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                        .receive(on: RunLoop.main)) { _ in
                        evaluateMemberSetup()       // a joined space's share and permissions arrive with the import
                    }
                    .sheet(item: $memberSetupSpace, onDismiss: { app.memberSetupSpaceID = nil }) { target in
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
                    .shoppingActivity(app, coordinator: services.shoppingActivity, context: services.context)
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

    @ViewBuilder
    private var windowContent: some View {
        if let route {
            WindowRouteView(route: route)
        } else {
            MainTabView()
        }
    }

    /// This window accepts the invitation it claimed. With no claim left (the claiming window closed) any window may.
    private var ownsInvitation: Bool { inbox.owner == nil || inbox.owner == windowID }

    /// Invitations wait in the inbox until the services exist, then are accepted one at a time, by a window the user
    /// is looking at (an active one).
    private func startNextInvitation() {
        guard scenePhase == .active, app.shareAcceptance.state == .idle, let next = inbox.takeNext() else { return }
        inbox.owner = windowID
        Task { await app.shareAcceptance.accept(next) }
    }

    private func attributionTracker(_ services: ServiceContainer) -> AttributionTracker {
        #if DEBUG
        if let override = app.attributionOverride { return override }
        #endif
        return services.attribution
    }

    /// Names and colours of this window's space's members, resolved when a flashing card asks.
    private func memberLookup(_ services: ServiceContainer) -> MemberLookup {
        let selection = selection
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
    /// Asked in one main window only, even when several windows show the household (N-03).
    private func evaluateMemberSetup() {
        guard route == nil, memberSetupSpace == nil, let services = app.services,
              let members = services.members, let sharing = services.sharing,
              let id = selection.selectedSpaceID, !memberSetupSkips.isSkipped(id),
              app.memberSetupSpaceID != id,
              let space = sharing.space(withPublicId: id),
              members.needsSetup(in: space) else { return }
        app.memberSetupSpaceID = id
        memberSetupSpace = MemberSetupTarget(space: space)
    }
}

/// A space waiting for first-visit member setup (`Space` itself is not Identifiable).
private struct MemberSetupTarget: Identifiable {
    let space: Space
    var id: NSManagedObjectID { space.objectID }
}
