import HomassyCore
import SwiftUI

/// Writes the space to a .homassy file and hands it to the system exporter.
struct ArchiveExportButton<Label: View>: View {
    let space: Space
    @ViewBuilder let label: () -> Label

    @State private var target: Space?

    var body: some View {
        Button(action: { target = space }, label: label)
            .archiveExporting($target)
    }
}

/// Exports `target` whenever it is set, presents the system exporter, and clears it afterwards.
/// A successful save counts as the last export for the backup reminder.
struct ArchiveExporting: ViewModifier {
    @Binding var target: Space?

    @Environment(ServiceContainer.self) private var services
    @Environment(BackupReminder.self) private var reminder
    @State private var document: HomassyArchiveDocument?
    @State private var isExporting = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: target) { _, space in
                if let space { export(space) }
            }
            .fileExporter(isPresented: $isExporting, document: document, contentType: .homassyArchive,
                          defaultFilename: document?.url.deletingPathExtension().lastPathComponent) { result in
                switch result {
                case .success: reminder.recordExport()
                case .failure(let error): errorMessage = error.localizedDescription
                }
                document = nil
                target = nil
            }
            .alert(Text("archive.export.failed"), isPresented: Binding(get: { errorMessage != nil },
                                                                      set: { if !$0 { errorMessage = nil } })) {
                Button("archive.ok", role: .cancel) {}
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
    }

    private func export(_ space: Space) {
        guard let archive = services.archive else {
            target = nil
            return
        }
        do {
            let url = try archive.makeExporter().export(space: space)
            document = HomassyArchiveDocument(url: url)
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
            target = nil
        }
    }
}

extension View {
    func archiveExporting(_ target: Binding<Space?>) -> some View {
        modifier(ArchiveExporting(target: target))
    }
}
