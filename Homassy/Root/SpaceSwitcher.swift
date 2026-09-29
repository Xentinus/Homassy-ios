import Combine
import CoreData
import HomassyCore
import SwiftUI

/// Toolbar menu listing Personal and every household, with a checkmark on the selected one, then New household
/// and Settings… (P1-07a: the Home app pattern, the settings of the selected space open as a sheet). The
/// switcher's own icon never changes; a persistent sync problem (P5-05) is shown with the system toolbar-item
/// badge instead (Apple-native, user choice 2026-09-26) — see `SpaceSwitcherToolbarItem` below, since the badge
/// is a modifier on the toolbar content, not on this view. The "Settings…" row still swaps to a warning
/// triangle while there's a problem, since that row is plain menu content, not a toolbar item.
struct SpaceSwitcher: View {
    @Environment(AppModel.self) private var app
    @Environment(SpaceSelection.self) private var selection
    @Environment(ServiceContainer.self) private var services
    @Environment(ArchiveImportRouter.self) private var archiveRouter
    @State private var spaces: [Space] = []
    @State private var isCreatingHousehold = false
    @State private var isShowingSettings = false
    /// Imports started in the settings sheet wait here until it has closed; the shell cannot present over it.
    @State private var settingsImports = ArchiveImportRouter()
    @State private var router = AppRouter.shared

    var body: some View {
        let current = selection.resolve(in: spaces)
        let name = current?.name ?? ""
        let hasProblem = services.syncStatus.bannerProblem != nil
        Menu {
            ForEach(spaces, id: \.objectID) { space in
                Button {
                    selection.select(space)
                } label: {
                    if space.objectID == current?.objectID {
                        Label(space.name, systemImage: "checkmark")
                    } else {
                        Text(space.name)
                    }
                }
            }
            Divider()
            Button("space.new", systemImage: "plus") { isCreatingHousehold = true }
                .disabled(services.sharing == nil)
                .accessibilityIdentifier("space.new")
            Divider()
            Button {
                isShowingSettings = true
            } label: {
                Label("space.settings", systemImage: hasProblem ? "exclamationmark.triangle.fill" : "gearshape")
            }
            .accessibilityIdentifier("space.settings")
        } label: {
            Label(name, systemImage: current?.kind == .household ? "house.fill" : "person.crop.circle")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityIdentifier("spaceSwitcher")
        .accessibilityLabel(hasProblem ? Text("space.syncProblem.accessibility \(name)") : Text(verbatim: name))
        .accessibilityHint(Text("space.switcher"))
        .sheet(isPresented: $isCreatingHousehold) {
            if let sharing = services.sharing { NewHouseholdSheet(service: sharing) }
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: handImportsToTheShell) {
            SpaceSettingsSheet()
                .environment(settingsImports)
        }
        .onChange(of: archiveRouter.pending?.id) { _, id in
            // A file opened from Files or Mail while the settings sheet is up: close the sheet first, then import.
            guard id != nil, isShowingSettings, let pending = archiveRouter.pending else { return }
            settingsImports.pending = pending
            archiveRouter.pending = nil
            isShowingSettings = false
        }
        .onChange(of: archiveRouter.errorMessage) { _, message in
            // Same hand-off as `pending` above, for a file that failed to open while the sheet is up.
            guard message != nil, isShowingSettings else { return }
            settingsImports.errorMessage = archiveRouter.errorMessage
            archiveRouter.errorMessage = nil
            isShowingSettings = false
        }
        .onChange(of: router.openCount) {
            // A notification tap or a quick action switches tabs behind the sheet (`MainTabView`); the sheet must
            // not linger over it.
            isShowingSettings = false
        }
        .onChange(of: app.shareAcceptance.state) { _, state in
            // The joining capsule and the failure alert live on `MainTabView`, under the sheet, and cannot present
            // over it: close the sheet as soon as acceptance is no longer idle.
            if state != .idle { isShowingSettings = false }
        }
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: app.persistence.viewContext)) { _ in
            reload()
        }
    }

    private func reload() {
        spaces = (try? app.spaceStore.allSpaces()) ?? []
    }

    /// Runs once the settings sheet is gone, so `MainTabView` can present the import sheet or its error.
    private func handImportsToTheShell() {
        if let pending = settingsImports.pending {
            settingsImports.pending = nil
            archiveRouter.pending = pending
        }
        if let message = settingsImports.errorMessage {
            settingsImports.errorMessage = nil
            archiveRouter.errorMessage = message
        }
    }
}

/// `SpaceSwitcher()`'s own toolbar item, with the system badge for a persistent sync problem (P5-05,
/// Apple-native, user choice 2026-09-26) — the same "!" the old Household tab badge used. `ToolbarItem` itself
/// has no `badge(_:)` in this SDK (only `TabContent` and `View` do), so the badge is applied to the switcher's
/// content view, inside the item, not to the toolbar content. Every screen with the switcher in its toolbar
/// uses this in place of a plain `ToolbarItem(placement: .topBarLeading) { SpaceSwitcher() }`.
struct SpaceSwitcherToolbarItem: ToolbarContent {
    @Environment(ServiceContainer.self) private var services

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            SpaceSwitcher()
                .badge(services.syncStatus.bannerProblem == nil ? nil : Text(verbatim: "!"))
        }
    }
}
