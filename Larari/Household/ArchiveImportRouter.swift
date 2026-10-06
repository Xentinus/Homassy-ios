import Foundation
import LarariCore
import Observation

/// Holds an archive waiting to be imported, whether it came from `.fileImporter` or from
/// `onOpenURL` (Files, Mail, AirDrop). `MainTabView` presents the import sheet for it, so a file opened
/// while the iCloud gate is showing waits here until the tabs appear.
@MainActor
@Observable
final class ArchiveImportRouter {
    struct Pending: Identifiable {
        let id = UUID()
        let url: URL
    }

    var pending: Pending?
    var errorMessage: String?

    func open(_ url: URL) {
        guard url.pathExtension.lowercased() == ArchivePackage.fileExtension else { return }
        do {
            pending = Pending(url: try ArchiveInbox.copyToTemporary(url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
