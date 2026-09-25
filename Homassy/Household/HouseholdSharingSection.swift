import Combine
import CoreData
import HomassyCore
import SwiftUI

/// The selected space's Members, Backup and Delete/Leave sections. Members and Delete/Leave are shown
/// only for households; the destructive action sits alone at the bottom of the list (HIG). Members holds
/// everything about people: the member list, former members, the user's own name/photo/colour and sharing.
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
    @State private var sharingPresentation: SharingPresentation?
    @State private var showsCloudNotice = false
    @State private var editingSelf = false
    @State private var showsFormer = false
    /// Bumped on every view-context change: member rows are computed, not observed.
    @State private var revision = 0

    var body: some View {
        let _ = revision
        Group {
            content
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in
            revision += 1
        }
    }

    @ViewBuilder private var content: some View {
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
        let rows = services.members?.memberRows(in: space) ?? []
        let current = rows.filter { $0.status != .departed }
        let former = rows.filter { $0.status == .departed }
        return Section {
            ForEach(current) { MemberRowView(row: $0) }
            if !former.isEmpty {
                DisclosureGroup(isExpanded: $showsFormer) {
                    ForEach(former) { MemberRowView(row: $0) }
                } label: {
                    Text("member.former \(former.count)")
                }
                .accessibilityIdentifier("member.former")
            }
            if let members = services.members, sharing.canEdit(space) {
                let needsName = members.needsSetup(in: space) || members.currentMember(in: space) == nil
                Button(needsName ? "member.setYourName" : "member.editSelf",
                       systemImage: needsName ? "person.crop.circle.badge.plus" : "pencil") { editingSelf = true }
                    .accessibilityIdentifier("member.editSelf")
                    // Its own sheet: the section already presents the sharing controller.
                    .sheet(isPresented: $editingSelf) {
                        MemberSetupView(service: members, space: space, userRecordName: services.userRecordName)
                    }
            }
            if role == .notShared {
                Button("household.sharing.share", systemImage: "person.2.badge.plus") {
                    run {
                        let share = try await sharing.shareExistingSpace(space)
                        if sharing.isCloudBacked {
                            sharingPresentation = SharingPresentation(share: share)
                        } else {
                            showsCloudNotice = true
                        }
                    }
                }
                .accessibilityIdentifier("household.sharing.share")
            } else {
                // One entry for owner and participant: the system sheet lists members, adds people
                // (owner) and offers Remove Me (participant).
                Button("household.sharing.manage", systemImage: "person.2") { presentSharing(sharing) }
                    .accessibilityIdentifier("household.sharing.manage")
            }
            #if DEBUG
            LabeledContent("household.sharing.zoneCheck") {
                Text(verbatim: "\(sharing.objectsOutsideShareZone(in: space).count)")
            }
            .accessibilityIdentifier("household.sharing.zoneCheck")
            #endif
        } header: {
            Text("member.section.title")
        }
        .disabled(isWorking)
        .sheet(item: $sharingPresentation) { presentation in
            CloudSharingView(share: presentation.share, space: space, sharing: sharing) { message in
                errorMessage = message
            }
            .ignoresSafeArea()
        }
        .alert(Text("household.sharing.cloudNeeded"), isPresented: $showsCloudNotice) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: SharingError.cloudUnavailable.errorDescription ?? "")
        }
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

    /// Local mode has no CloudKit behind it, so it explains that instead of opening the system sheet.
    private func presentSharing(_ sharing: SharingService) {
        guard sharing.isCloudBacked else {
            showsCloudNotice = true
            return
        }
        guard let share = sharing.share(for: space) else { return }
        sharingPresentation = SharingPresentation(share: share)
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

/// One member: avatar with the colour ring, name, "You", and the role or status.
struct MemberRowView: View {
    let row: MemberRow

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(name: row.displayName, colorSeed: row.colorSeed, colorKey: row.colorKey, avatar: row.avatar)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: row.displayName)
                    if row.isCurrentUser {
                        Text("member.you").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(row.isCurrentUser ? "member.row.me" : "member.row")
    }

    private var subtitle: LocalizedStringKey {
        switch row.status {
        case .invited: "member.status.invited"
        case .departed: "member.status.departed"
        case .active:
            if row.isOwner { "household.role.owner" } else if row.permission == .readOnly { "member.status.viewOnly" } else { "member.status.canEdit" }
        }
    }
}
