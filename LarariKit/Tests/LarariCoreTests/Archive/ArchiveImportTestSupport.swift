import Foundation
@testable import LarariCore

extension ArchiveTestStack {
    /// Writes `contents` as a .larari file. Manifest counts are recomputed, so tests only edit data.
    /// By default the archive's household is owned by the importing user, so every member is importable
    /// (P5-02a); pass `ownedBy` to import someone else's household.
    func writeArchive(_ contents: ArchiveContents, images: [String: Data] = [:], ownedBy owner: String? = nil) throws -> URL {
        var contents = contents
        contents.data.space.createdBy = owner ?? user
        contents.manifest.counts = contents.data.counts
        let url = temporaryURL()
        try ArchivePackage.write(contents, images: images, to: url)
        return url
    }

    func importer(canEdit: @escaping @MainActor (Space) -> Bool = { _ in true }) -> ArchiveImporter {
        ArchiveImporter(persistence: persistence, spaceStore: spaceStore, userRecordName: user, canEdit: canEdit)
    }

    func spaceCount() throws -> Int { try count(Space.self) }
}
