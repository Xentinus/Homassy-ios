import Foundation

public enum ArchiveInbox {
    /// Copies a picked or opened file into a private temporary folder. It handles security-scoped
    /// URLs from `.fileImporter` and coordinated reads for iCloud Drive files that are not yet
    /// downloaded. The import works on the copy, so the original file is never touched.
    public static func copyToTemporary(_ url: URL) throws -> URL {
        let fileManager = FileManager.default
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let folder = fileManager.temporaryDirectory
            .appending(path: "HomassyImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: url.lastPathComponent)

        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            do {
                try fileManager.copyItem(at: readableURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return destination
    }
}
