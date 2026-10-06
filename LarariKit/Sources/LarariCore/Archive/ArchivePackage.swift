import CryptoKit
import Foundation
import ZIPFoundation

public enum ArchiveImages {
    /// "images/<lowercase hex SHA-256>.jpg". Identical bytes give the same path, which deduplicates.
    public static func reference(for data: Data) -> String {
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "images/\(hex).jpg"
    }
}

public enum ArchivePackage {
    public static let manifestEntry = "manifest.json"
    public static let dataEntry = "data.json"
    public static let fileExtension = "larari"

    public struct Loaded: Sendable {
        public let contents: ArchiveContents
        public let images: [String: Data]

        public init(contents: ArchiveContents, images: [String: Data]) {
            self.contents = contents
            self.images = images
        }
    }

    /// Writes a zip at `destination`, replacing any file already there. `images` must contain
    /// every reference in `contents.data`; extra entries are ignored.
    public static func write(_ contents: ArchiveContents, images: [String: Data], to destination: URL) throws {
        let fileManager = FileManager.default
        let files = try ArchiveCodec.encode(contents)
        let references = contents.data.imageReferences.sorted()
        for reference in references where images[reference] == nil {
            throw ArchiveError.missingImage(reference)
        }

        let staging = fileManager.temporaryDirectory
            .appending(path: "LarariArchive-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging.appending(path: "images", directoryHint: .isDirectory),
                                        withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try files.manifest.write(to: staging.appending(path: manifestEntry))
        try files.data.write(to: staging.appending(path: dataEntry))
        for reference in references {
            try images[reference]?.write(to: staging.appending(path: reference))
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let archive = try Archive(url: destination, accessMode: .create)
        for entry in [manifestEntry, dataEntry] + references {
            // JPEGs are already compressed; deflating them only costs time.
            try archive.addEntry(with: entry, relativeTo: staging,
                                 compressionMethod: entry.hasPrefix("images/") ? .none : .deflate)
        }
    }

    /// Reads and fully validates an archive: the schema version first, then JSON, counts, image
    /// references and image checksums. Nothing is written anywhere.
    public static func read(_ url: URL) throws -> Loaded {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ArchiveError.corrupted("not a zip archive: \(error)")
        }

        func extract(_ path: String) throws -> Data {
            guard let entry = archive[path] else { throw ArchiveError.missingEntry(path) }
            var data = Data()
            do {
                _ = try archive.extract(entry, consumer: { data.append($0) })
            } catch {
                throw ArchiveError.corrupted("\(path): \(error)")
            }
            return data
        }

        let manifestData = try extract(manifestEntry)
        _ = try ArchiveCodec.decodeManifest(manifestData)          // newer versions fail before data.json is read
        let contents = try ArchiveCodec.decode(manifest: manifestData, data: try extract(dataEntry))

        var images: [String: Data] = [:]
        for reference in contents.data.imageReferences.sorted() {
            guard archive[reference] != nil else { throw ArchiveError.missingImage(reference) }
            let bytes = try extract(reference)
            guard ArchiveImages.reference(for: bytes) == reference else {
                throw ArchiveError.imageChecksumMismatch(reference)
            }
            images[reference] = bytes
        }
        return Loaded(contents: contents, images: images)
    }
}
