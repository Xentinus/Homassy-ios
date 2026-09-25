import HomassyCore
import SwiftUI

/// The monthly backup nudge at the top of the Inventory tab. "Export now" and "Not now" both hide it.
struct BackupReminderBanner: View {
    let space: Space
    @Environment(BackupReminder.self) private var reminder

    var body: some View {
        if reminder.shouldRemind() {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("backup.banner.title").font(.headline)
                    Text("backup.banner.message").font(.subheadline).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack { buttons }
                        VStack(alignment: .leading) { buttons }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.bottom, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("backup.banner")
        }
    }

    @ViewBuilder private var buttons: some View {
        ArchiveExportButton(space: space) { Text("backup.banner.export") }
            .buttonStyle(.borderedProminent)
        Button("backup.banner.dismiss") { reminder.dismiss() }
            .buttonStyle(.bordered)
    }
}
