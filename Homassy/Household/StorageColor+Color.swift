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
        .custom(color.rgbHex)
    }
}
