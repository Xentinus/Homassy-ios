import Foundation

public enum FeatureError {
    public static func message(for error: any Error) -> String {
        if let description = (error as? any LocalizedError)?.errorDescription { return description }
        return String(localized: "shopping.error.generic", bundle: .module)
    }
}

/// List colours are tags (a dot on the card), never member colours.
public enum ShoppingListPalette {
    public static let colors = ["#E0A458", "#D9534F", "#5CB85C", "#4A90D9", "#9B59B6", "#F0C419", "#1ABC9C", "#8E7F6F"]

    /// A colour picked with the colour picker rather than from the palette.
    public static func isCustom(_ hex: String?) -> Bool {
        guard let hex, HexColor.parse(hex) != nil else { return false }
        return !colors.contains { $0.caseInsensitiveCompare(hex) == .orderedSame }
    }

    /// `#rrggbb` or `rrggbb`, as 0…1 components.
    public static func rgb(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard let value = HexColor.parse(hex.hasPrefix("#") ? hex : "#" + hex) else { return nil }
        let c = HexColor.components(value)
        return (Double(c.r) / 255, Double(c.g) / 255, Double(c.b) / 255)
    }
}
