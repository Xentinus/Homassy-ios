import LarariCore
import SwiftUI
import UniformTypeIdentifiers

/// Wraps an already written .larari file for `.fileExporter`, without loading it into memory.
nonisolated struct LarariArchiveDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.larariArchive]
    let url: URL

    init(url: URL) { self.url = url }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}
