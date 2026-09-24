import HomassyCore
import SwiftUI
import UIKit

extension StorageColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        case .custom(let hex): Color(hex: hex)
        }
    }

    /// The picked colour as a custom storage colour, clamped to 24-bit sRGB (the colour picker has no opacity).
    static func custom(from color: Color) -> StorageColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return .custom(byte(red) << 16 | byte(green) << 8 | byte(blue))
    }
}
