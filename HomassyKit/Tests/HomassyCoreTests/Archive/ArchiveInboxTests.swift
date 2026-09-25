import Foundation
import Testing
import UniformTypeIdentifiers
@testable import HomassyCore

@Suite("Archive inbox")
struct ArchiveInboxTests {
    @Test func copiesIntoAFreshTemporaryFolder() throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString).homassy")
        try Data("zip bytes".utf8).write(to: source)

        let first = try ArchiveInbox.copyToTemporary(source)
        let second = try ArchiveInbox.copyToTemporary(source)

        #expect(first.lastPathComponent == source.lastPathComponent)
        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data("zip bytes".utf8))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func missingSourceThrows() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "nope-\(UUID().uuidString).homassy")
        #expect(throws: (any Error).self) { try ArchiveInbox.copyToTemporary(missing) }
    }

    @Test func archiveTypeIdentifier() {
        #expect(UTType.homassyArchive.identifier == "com.homassy.archive")
    }
}
