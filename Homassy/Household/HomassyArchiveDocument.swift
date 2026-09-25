import HomassyCore
import SwiftUI
import UniformTypeIdentifiers

/// Wraps an already written .homassy file for `.fileExporter`, without loading it into memory.
nonisolated struct HomassyArchiveDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.homassyArchive]
    let url: URL

    init(url: URL) { self.url = url }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}
