import HomassyCore
import SwiftUI

/// A shopping list's tag colour (`#rrggbb`), or a neutral dot when it has none.
enum ListColor {
    static func color(_ hex: String?) -> Color {
        guard let hex, let value = HexColor.parse(hex) else { return Color.secondary.opacity(0.35) }
        return Color(hex: value)
    }

    /// `#rrggbb` of a picked colour (the storage-colour conversion: sRGB, opacity dropped).
    static func hex(from color: Color) -> String { StorageColor.custom(from: color).rawValue }
}
