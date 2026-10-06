import Foundation

/// 24-bit sRGB colours written as `0xRRGGBB`.
public enum HexColor {
    public static func components(_ hex: UInt32) -> (r: UInt8, g: UInt8, b: UInt8) {
        (UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }

    /// Strict `#rrggbb` (either case), the same rule as the web app's `isHexColor`.
    public static func parse(_ string: String) -> UInt32? {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count == 7, scalars[0] == "#" else { return nil }
        var value: UInt32 = 0
        for scalar in scalars.dropFirst() {
            guard let digit = hexDigit(scalar) else { return nil }
            value = value << 4 | digit
        }
        return value
    }

    public static func format(_ hex: UInt32) -> String {
        let c = components(hex)
        return "#" + [c.r, c.g, c.b].map { byte in
            let text = String(byte, radix: 16)
            return text.count == 1 ? "0" + text : text
        }.joined()
    }

    private static func hexDigit(_ scalar: Unicode.Scalar) -> UInt32? {
        switch scalar {
        case "0"..."9": scalar.value - 48
        case "a"..."f": scalar.value - 87
        case "A"..."F": scalar.value - 55
        default: nil
        }
    }
}
