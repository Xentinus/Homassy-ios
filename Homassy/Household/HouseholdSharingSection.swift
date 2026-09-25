import CoreData
import HomassyCore
import SwiftUI

/// The selected space's Sharing, Backup and Delete/Leave sections. Sharing and Delete/Leave are shown
/// only for households; the destructive action sits alone at the bottom of the list (HIG).
struct HouseholdSpaceSections: View {
    let space: Space

    @Environment(ServiceContainer.self) private var services
    @Environment(\.requestExport) private var requestExport
    @Environment(SpaceSelection.self) private var selection
    @State private var confirmLeave = false
    @State private var confirmDeleteStep1 = false
    @State private var confirmDeleteStep2 = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        if space.managedObjectContext != nil {
            if let sharing = services.sharing, space.kind == .household {
                let role = sharing.role(for: space)
                sharingSection(sharing, role: role)
                ArchiveSection(space: space)
                destructiveSection(sharing, role: role)
            } else {
                ArchiveSection(space: space)
            }
        }
    }

    private func sharingSection(_ sharing: SharingService, role: HouseholdRole) -> some View {
        Section {
            LabeledContent("household.sharing.role") {
                Text(role.title)
            }
            .accessibilityIdentifier("household.sharing.role")
            if role == .notShared {
                Button("household.sharing.share", systemImage: "person.2.badge.plus") {
                    run { _ = try await sharing.shareExistingSpace(space) }
                }
                .accessibilityIdentifier("household.sharing.share")
            }
            #if DEBUG
            LabeledContent("household.sharing.zoneCheck") {
                Text(verbatim: "\(sharing.objectsOutsideShareZone(in: space).count)")
            }
            .accessibilityIdentifier("household.sharing.zoneCheck")
            #endif
        } header: {
            Text("household.sharing.title")
        }
        .disabled(isWorking)
        .alert(Text("household.error.title"),
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private func destructiveSection(_ sharing: SharingService, role: HouseholdRole) -> some View {
        Section {
            if role == .participant {
                Button("household.sharing.leave", role: .destructive) { confirmLeave = true }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("household.sharing.leave")
            } else {
                Button("household.sharing.delete", role: .destructive) { confirmDeleteStep1 = true }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("household.sharing.delete")
            }
        } footer: {
            if role == .owner {
                Text("household.sharing.ownerLoss")
            }
        }
        .disabled(isWorking)
        .confirmationDialog(Text("household.leave.confirm \(space.name)"), isPresented: $confirmLeave,
                            titleVisibility: .visible) {
            Button("household.exportFirst") { requestExport(space) }
            Button("household.sharing.leave", role: .destructive) { run { try await sharing.leave(space) } }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("household.leave.message")
        }
        .confirmationDialog(Text("household.delete.confirm \(space.name)"), isPresented: $confirmDeleteStep1,
                            titleVisibility: .visible) {
            Button("household.exportFirst") { requestExport(space) }
            Button("household.delete.continue", role: .destructive) { confirmDeleteStep2 = true }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("household.delete.message")
        }
        .alert(Text("household.delete.final.title"), isPresented: $confirmDeleteStep2) {
            Button("household.sharing.delete", role: .destructive) { run { try await sharing.deleteHousehold(space) } }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("household.delete.final.message")
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await action()
                if space.isDeleted || space.managedObjectContext == nil {
                    selection.selectedSpaceID = nil      // falls back to Personal
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

extension HouseholdRole {
    var title: LocalizedStringKey {
        switch self {
        case .owner: "household.role.owner"
        case .participant: "household.role.participant"
        case .notShared: "household.role.notShared"
        }
    }
}
