import Foundation
import Testing
import UniformTypeIdentifiers
@testable import LarariCore

@Suite("Archive inbox")
struct ArchiveInboxTests {
    @Test func copiesIntoAFreshTemporaryFolder() throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString).larari")
        try Data("zip bytes".utf8).write(to: source)

        let first = try ArchiveInbox.copyToTemporary(source)
        let second = try ArchiveInbox.copyToTemporary(source)

        #expect(first.lastPathComponent == source.lastPathComponent)
        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data("zip bytes".utf8))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func missingSourceThrows() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "nope-\(UUID().uuidString).larari")
        #expect(throws: (any Error).self) { try ArchiveInbox.copyToTemporary(missing) }
    }

    @Test func archiveTypeIdentifier() {
        #expect(UTType.larariArchive.identifier == "app.larari.archive")
        // Not an archive to the system, otherwise Files unpacks it on tap instead of opening Larari.
        #expect(UTType.larariArchive.conforms(to: .data))
        #expect(!UTType.larariArchive.conforms(to: .archive))
    }
}
