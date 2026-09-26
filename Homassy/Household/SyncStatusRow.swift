import HomassyCore
import SwiftUI

/// The space settings sheet's iCloud row: last sync, syncing, or the current problem. Local mode says sync
/// needs iCloud.
struct SyncStatusRow: View {
    @Environment(SyncStatusModel.self) private var status
    @Environment(ServiceContainer.self) private var services

    var body: some View {
        Group {
            if services.sharing?.isCloudBacked == false {
                // Local mode: no CloudKit behind the store (README "Local development mode").
                Label("sync.localOnly", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            } else {
                cloudStatus
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sync.status")
    }

    private var cloudStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(status.currentError == nil ? Color.secondary : Palette.expirySoon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("sync.title")
                Text(verbatim: detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status.isSyncing { ProgressView() }
        }
    }

    private var symbol: String {
        if status.currentError != nil { return "exclamationmark.icloud" }
        return status.isSyncing ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud"
    }

    private var detail: String {
        if let problem = status.currentError { return problem.message }
        if let last = status.lastSuccessfulSync {
            return String(localized: "sync.lastSynced \(last.formatted(.relative(presentation: .named)))")
        }
        return String(localized: "sync.waiting")
    }
}
