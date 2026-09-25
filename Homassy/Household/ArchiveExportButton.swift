import HomassyCore
import SwiftUI

/// Writes the space to a .homassy file and hands it to the system exporter. A successful save counts as
/// the last export for the backup reminder.
struct ArchiveExportButton<Label: View>: View {
    let space: Space
    @ViewBuilder let label: () -> Label

    @Environment(ServiceContainer.self) private var services
    @Environment(BackupReminder.self) private var reminder
    @State private var document: HomassyArchiveDocument?
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        Button(action: export, label: label)
            .fileExporter(isPresented: $isExporting, document: document, contentType: .homassyArchive,
                          defaultFilename: document?.url.deletingPathExtension().lastPathComponent) { result in
                switch result {
                case .success: reminder.recordExport()
                case .failure(let error): errorMessage = error.localizedDescription
                }
                document = nil
            }
            .alert(Text("archive.export.failed"), isPresented: Binding(get: { errorMessage != nil },
                                                                      set: { if !$0 { errorMessage = nil } })) {
                Button("archive.ok", role: .cancel) {}
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
    }

    private func export() {
        guard let archive = services.archive else { return }
        do {
            let url = try archive.makeExporter().export(space: space)
            document = HomassyArchiveDocument(url: url)
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
