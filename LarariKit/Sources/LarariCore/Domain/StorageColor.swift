import Foundation

/// A storage location's colour: one of the fixed palette names, or any colour the user picked.
///
/// Stored in `StorageLocation.color` as the raw value: the palette name (`"blue"`), so every
/// platform maps it to its own system colour, or `#rrggbb` for a custom colour, the same format
/// the web app uses.
public enum StorageColor: Hashable, Sendable, Identifiable, RawRepresentable {
    case red, orange, yellow, green, teal, blue, purple, gray
    /// A user-picked 24-bit sRGB colour, `0xRRGGBB`.
    case custom(UInt32)

    /// The fixed palette offered as swatches, in display order.
    public static let palette: [StorageColor] = [.red, .orange, .yellow, .green, .teal, .blue, .purple, .gray]

    /// A palette name, or strict `#rrggbb` in either case. Anything else is `nil`.
    public init?(rawValue: String) {
        if let preset = Self.palette.first(where: { $0.rawValue == rawValue }) {
            self = preset
        } else if let hex = HexColor.parse(rawValue) {
            self = .custom(hex)
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .red: "red"
        case .orange: "orange"
        case .yellow: "yellow"
        case .green: "green"
        case .teal: "teal"
        case .blue: "blue"
        case .purple: "purple"
        case .gray: "gray"
        case .custom(let hex): HexColor.format(hex & 0xFFFFFF)
        }
    }

    public var id: String { rawValue }

    public var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    public var localizedName: String {
        let key = isCustom ? "storageColor.custom" : "storageColor.\(rawValue)"
        return Bundle.module.localizedString(forKey: key, value: nil, table: "Localizable")
    }
}

extension StorageLocation {
    /// `nil` for no colour and for values this version does not know.
    public var storageColor: StorageColor? { color.flatMap(StorageColor.init(rawValue:)) }
}
