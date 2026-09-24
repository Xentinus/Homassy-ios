import Foundation

/// The fixed palette for storage locations. Stored in `StorageLocation.color` as the raw name,
/// so every platform can map it to its own system colour.
public enum StorageColor: String, CaseIterable, Sendable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, gray

    public var id: String { rawValue }

    public var localizedName: String {
        Bundle.module.localizedString(forKey: "storageColor.\(rawValue)", value: nil, table: "Localizable")
    }
}

extension StorageLocation {
    /// `nil` for no colour and for values this version does not know.
    public var storageColor: StorageColor? { color.flatMap(StorageColor.init(rawValue:)) }
}
