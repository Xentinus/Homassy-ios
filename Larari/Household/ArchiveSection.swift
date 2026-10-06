import LarariCore
import SwiftUI

/// The space settings sheet's Backup section: export the selected space, import a file, and the last export date.
struct ArchiveSection: View {
    let space: Space

    @Environment(ArchiveImportRouter.self) private var router
    @Environment(BackupReminder.self) private var reminder
    @State private var isImporting = false

    var body: some View {
        Section {
            ArchiveExportButton(space: space) {
                Label { Text("archive.export.button \(space.name)") } icon: { Image(systemName: "square.and.arrow.up") }
            }
            .accessibilityIdentifier("archive.export")

            Button { isImporting = true } label: {
                Label("archive.import.button", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("archive.import")

            LabeledContent("archive.lastExport") {
                if let last = reminder.lastExportAt {
                    Text(last, format: .dateTime.year().month().day())
                } else {
                    Text("archive.lastExport.never")
                }
            }
        } header: {
            Text("archive.section.title")
        } footer: {
            Text("archive.section.footer")
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.larariArchive]) { result in
            switch result {
            case .success(let url): router.open(url)
            case .failure(let error): router.errorMessage = error.localizedDescription
            }
        }
    }
}
