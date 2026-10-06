import LarariCore
import SwiftUI

/// A persistent sync problem (§8), the Apple-native way (user choice, 2026-09-25): the system toolbar-item
/// badge on the space menu (P1-07a) and this callout at the top of the space settings sheet, with the actions
/// where they apply. Like Settings' "iCloud storage full" row, it never covers other screens' content.
struct SyncProblemCallout: View {
    let problem: SyncProblem
    @Environment(SyncStatusModel.self) private var status
    @Environment(ServiceContainer.self) private var services
    @Environment(\.requestExport) private var requestExport
    @State private var errorMessage: String?

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.expirySoon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("sync.callout.title").font(.headline)
                    Text(verbatim: problem.message).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sync.callout")
            if let space = goneSpace {
                Button("household.new.export", systemImage: "square.and.arrow.up") { requestExport(space) }
                Button("sync.removeLocalCopy", systemImage: "trash", role: .destructive) {
                    Task {
                        do {
                            try await services.sharing?.removeLocalCopy(of: space)
                            status.resolveZoneGone()
                        } catch {
                            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }
            }
        } footer: {
            if goneSpace != nil { Text("sync.zoneGone.footer") }
        }
        .alert(Text("household.error.title"),
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var goneSpace: Space? {
        guard case let .zoneGone(zone?) = problem else { return nil }
        return services.sharing?.space(inZone: zone)
    }
}
