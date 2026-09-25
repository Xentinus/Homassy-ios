import Foundation

public enum ArchiveError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// The associated text is for logs, never shown.
    case corrupted(String)
    case countMismatch
    case invalidImageReference(String)
    case missingEntry(String)
    case missingImage(String)
    case imageChecksumMismatch(String)
    case duplicatePublicId(UUID)
    case brokenReference(entity: ArchiveEntity, publicId: UUID, field: String)
    case unsavedChanges

    var catalogKey: String {
        switch self {
        case .unsupportedSchemaVersion: "archive.error.newerVersion"
        case .unsavedChanges: "archive.error.unsavedChanges"
        case .corrupted, .countMismatch, .invalidImageReference, .missingEntry, .missingImage,
             .imageChecksumMismatch, .duplicatePublicId, .brokenReference:
            "archive.error.damaged"
        }
    }

    public var errorDescription: String? {
        Bundle.module.localizedString(forKey: catalogKey, value: nil, table: "Localizable")
    }
}
