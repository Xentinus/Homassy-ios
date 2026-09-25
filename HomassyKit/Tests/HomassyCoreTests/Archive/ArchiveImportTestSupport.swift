import Foundation
@testable import HomassyCore

extension ArchiveTestStack {
    /// Writes `contents` as a .homassy file. Manifest counts are recomputed, so tests only edit data.
    func writeArchive(_ contents: ArchiveContents, images: [String: Data] = [:]) throws -> URL {
        var contents = contents
        contents.manifest.counts = contents.data.counts
        let url = temporaryURL()
        try ArchivePackage.write(contents, images: images, to: url)
        return url
    }

    func importer() -> ArchiveImporter {
        ArchiveImporter(persistence: persistence, spaceStore: spaceStore, userRecordName: user)
    }

    func spaceCount() throws -> Int { try count(Space.self) }
}
