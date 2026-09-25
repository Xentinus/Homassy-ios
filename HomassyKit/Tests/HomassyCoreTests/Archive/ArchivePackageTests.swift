import Foundation
import Testing
import ZIPFoundation
@testable import HomassyCore

@Suite("Archive package")
struct ArchivePackageTests {
    @Test func imageReferenceIsSha256() {
        // SHA-256("abc") is a well-known test vector.
        #expect(ArchiveImages.reference(for: Data("abc".utf8))
                == "images/ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad.jpg")
    }

    @Test func writeThenReadRoundTrips() throws {
        var contents = ArchiveSamples.sampleV1
        let photo = Data(repeating: 7, count: 300)
        let ref = ArchiveImages.reference(for: photo)
        contents.data.products[0].image = ref
        contents.manifest.counts = contents.data.counts
        let url = FileManager.default.temporaryDirectory.appending(path: "pkg-\(UUID().uuidString).homassy")

        try ArchivePackage.write(contents, images: [ref: photo], to: url)
        let loaded = try ArchivePackage.read(url)

        #expect(loaded.contents == contents)
        #expect(loaded.images == [ref: photo])
        let archive = try Archive(url: url, accessMode: .read)
        #expect(Set(archive.map(\.path)) == ["manifest.json", "data.json", ref])
    }

    @Test func writeReplacesAnExistingFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pkg-\(UUID().uuidString).homassy")
        try Data("old".utf8).write(to: url)
        try ArchivePackage.write(ArchiveSamples.sampleV1, images: [:], to: url)
        #expect(try ArchivePackage.read(url).contents == ArchiveSamples.sampleV1)
    }

    @Test func missingImageBytesFailTheWrite() throws {
        var contents = ArchiveSamples.sampleV1
        let ref = "images/" + String(repeating: "c", count: 64) + ".jpg"
        contents.data.products[0].image = ref
        contents.manifest.counts = contents.data.counts
        let url = FileManager.default.temporaryDirectory.appending(path: "pkg-\(UUID().uuidString).homassy")
        #expect(throws: ArchiveError.missingImage(ref)) {
            try ArchivePackage.write(contents, images: [:], to: url)
        }
    }

    @Test func readRejectsNonZip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "garbage-\(UUID().uuidString).homassy")
        try Data("definitely not a zip".utf8).write(to: url)
        let error = #expect(throws: ArchiveError.self) { try ArchivePackage.read(url) }
        guard case .corrupted = error else {
            Issue.record("expected .corrupted, got \(String(describing: error))")
            return
        }
    }

    @Test func readRejectsMissingDataJSON() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "nodata-\(UUID().uuidString).homassy")
        let files = try ArchiveCodec.encode(ArchiveSamples.sampleV1)
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addEntry(with: "manifest.json", type: .file, uncompressedSize: Int64(files.manifest.count),
                             provider: { position, size in
                                 files.manifest.subdata(in: Int(position)..<Int(position) + size)
                             })
        #expect(throws: ArchiveError.missingEntry("data.json")) { try ArchivePackage.read(url) }
    }

    @Test func readRejectsImageWithWrongChecksum() throws {
        var contents = ArchiveSamples.sampleV1
        let ref = ArchiveImages.reference(for: Data("real".utf8))
        contents.data.products[0].image = ref
        contents.manifest.counts = contents.data.counts
        let url = FileManager.default.temporaryDirectory.appending(path: "badsum-\(UUID().uuidString).homassy")
        try ArchivePackage.write(contents, images: [ref: Data("tampered".utf8)], to: url)
        #expect(throws: ArchiveError.imageChecksumMismatch(ref)) { try ArchivePackage.read(url) }
    }
}
