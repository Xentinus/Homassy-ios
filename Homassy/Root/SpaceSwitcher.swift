import Combine
import CoreData
import HomassyCore
import SwiftUI

/// Toolbar menu listing Personal and every household, with a checkmark on the selected one, then New household
/// and Settings… (P1-07a: the Home app pattern, the settings of the selected space open as a sheet). A persistent
/// sync problem swaps the menu's icon for a warning triangle (P5-05): the iOS 26 Liquid Glass toolbar chrome
/// re-renders a toolbar button's own icon and title from a `Label`, but discards a separately overlaid badge, so
/// a dot drawn on top of the icon never actually appears; changing the icon itself always does.
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
            Label(name, systemImage: hasProblem ? "exclamationmark.triangle.fill"
                                                 : (current?.kind == .household ? "house.fill" : "person.crop.circle"))
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
