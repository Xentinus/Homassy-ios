import Foundation

public enum ArchiveCodec {
    public static let supportedSchemaVersion = 1

    public static func makeEncoder(timeZone: TimeZone) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ArchiveDate.format(date, timeZone: timeZone))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ArchiveDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container,
                                                       debugDescription: "Invalid ISO-8601 date \"\(text)\"")
            }
            return date
        }
        return decoder
    }

    /// Encodes with the manifest's time zone, so every date carries the exporting device's offset.
    public static func encode(_ contents: ArchiveContents) throws -> ArchiveFiles {
        let timeZone = TimeZone(identifier: contents.manifest.timeZone) ?? .gmt
        let encoder = makeEncoder(timeZone: timeZone)
        return ArchiveFiles(manifest: try encoder.encode(contents.manifest),
                            data: try encoder.encode(contents.data))
    }

    /// Checks `schemaVersion` before anything else, so a newer file is reported as newer even when
    /// the rest of its manifest has changed shape.
    public static func decodeManifest(_ data: Data) throws -> ArchiveManifest {
        struct VersionProbe: Decodable { let schemaVersion: Int }
        let decoder = makeDecoder()
        let probe: VersionProbe
        do {
            probe = try decoder.decode(VersionProbe.self, from: data)
        } catch {
            throw ArchiveError.corrupted("manifest.json: \(error)")
        }
        guard probe.schemaVersion >= 1 else {
            throw ArchiveError.corrupted("manifest.json: schemaVersion \(probe.schemaVersion)")
        }
        guard probe.schemaVersion <= supportedSchemaVersion else {
            throw ArchiveError.unsupportedSchemaVersion(found: probe.schemaVersion,
                                                        supported: supportedSchemaVersion)
        }
        do {
            return try decoder.decode(ArchiveManifest.self, from: data)
        } catch {
            throw ArchiveError.corrupted("manifest.json: \(error)")
        }
    }

    public static func decode(manifest manifestData: Data, data archiveData: Data) throws -> ArchiveContents {
        let manifest = try decodeManifest(manifestData)
        let data: ArchiveData
        do {
            data = try makeDecoder().decode(ArchiveData.self, from: archiveData)
        } catch {
            throw ArchiveError.corrupted("data.json: \(error)")
        }
        for reference in data.imageReferences.sorted() where !isValidImageReference(reference) {
            throw ArchiveError.invalidImageReference(reference)
        }
        guard data.counts == manifest.counts else { throw ArchiveError.countMismatch }
        return ArchiveContents(manifest: manifest, data: data)
    }

    public static func isValidImageReference(_ reference: String) -> Bool {
        reference.wholeMatch(of: #/images\/[0-9a-f]{64}\.jpg/#) != nil
    }
}
