import Foundation

/// Identity colour for a member, ported from the web app's `utils/memberColors.ts`.
///
/// Always an accent (ring, border, dot), never text or a fill. The preset order is load-bearing:
/// `preset(for:)` indexes it modulo its length, so reordering or resizing it repaints every member.
/// One of the eight curated member colours: a light and a dark accent, plus the avatar gradient.
public struct MemberColorPreset: Equatable, Sendable {
    public let key: String
    public let light: UInt32
    public let dark: UInt32
    public let gradient: (from: UInt32, to: UInt32)

    public static func == (lhs: MemberColorPreset, rhs: MemberColorPreset) -> Bool {
        lhs.key == rhs.key && lhs.light == rhs.light && lhs.dark == rhs.dark
            && lhs.gradient.from == rhs.gradient.from && lhs.gradient.to == rhs.gradient.to
    }
}

public enum MemberColor {
    public typealias Preset = MemberColorPreset

    /// Frozen: same length and order as the web app's `MEMBER_COLORS`.
    public static let presets: [Preset] = [
        Preset(key: "rose", light: 0xF43F5E, dark: 0xFB7185, gradient: (0xE11D48, 0xFB7185)),
        Preset(key: "amber", light: 0xB45309, dark: 0xFBBF24, gradient: (0xD97706, 0xFBBF24)),
        Preset(key: "lime", light: 0x4D7C0F, dark: 0xA3E635, gradient: (0x4D7C0F, 0xA3E635)),
        Preset(key: "teal", light: 0x0F766E, dark: 0x2DD4BF, gradient: (0x0D9488, 0x2DD4BF)),
        Preset(key: "sky", light: 0x0369A1, dark: 0x38BDF8, gradient: (0x0284C7, 0x38BDF8)),
        Preset(key: "indigo", light: 0x6366F1, dark: 0x818CF8, gradient: (0x4F46E5, 0x818CF8)),
        Preset(key: "violet", light: 0x8B5CF6, dark: 0xA78BFA, gradient: (0x7C3AED, 0xA78BFA)),
        Preset(key: "fuchsia", light: 0xD946EF, dark: 0xE879F9, gradient: (0xC026D3, 0xE879F9)),
    ]

    /// The Homassy brand colour. A member can pick it by hand, but the hash never assigns it, so automatic colours
    /// keep matching the web app's eight-entry palette. Mocha 700 / 400: the 500 step is only 2.8:1 on white.
    public static let mocha = Preset(key: "mocha", light: 0x8B7355, dark: 0xC9B8A0, gradient: (0xA0825B, 0xC9B8A0))

    /// Everything a member can choose from: the hashed palette, then Mocha.
    public static let selectablePresets: [Preset] = presets + [mocha]

    /// Resolves a hand-picked preset key, such as a stored override. Unknown keys give `nil`.
    public static func preset(forKey key: String) -> Preset? {
        selectablePresets.first { $0.key == key }
    }

    /// A member's colour: the hand-picked key when it is known, otherwise the automatic one from the seed.
    public static func resolve(key: String?, seed: String) -> Preset {
        key.flatMap(preset(forKey:)) ?? preset(for: seed)
    }

    /// `pickMemberColor`: FNV-1a of the normalised seed, modulo the palette size.
    public static func preset(for seed: String) -> Preset {
        presets[Int(fnv1a(normalise(seed)) % UInt32(presets.count))]
    }

    /// Convenience only: hue in degrees (0..<360) of the chosen preset's light accent.
    /// Draw with `preset(for:)` (or `Color.memberAccent(seed:)` in the app), not with this.
    public static func hue(for seed: String) -> Double {
        hue(ofHex: preset(for: seed).light)
    }

    /// `normalise`: lower-cased, dashes removed, so a formatted and a bare GUID match.
    public static func normalise(_ seed: String) -> String {
        seed.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// 32-bit FNV-1a over UTF-16 code units, the same units JavaScript's `charCodeAt` returns.
    /// `Math.imul(h, 0x01000193) >>> 0` is a wrapping 32-bit multiply.
    public static func fnv1a(_ input: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for unit in input.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x0100_0193
        }
        return hash
    }

    /// The web app's `hexToHsl` hue component.
    static func hue(ofHex hex: UInt32) -> Double {
        let c = HexColor.components(hex)
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let maxValue = max(r, g, b), minValue = min(r, g, b)
        guard maxValue != minValue else { return 0 }
        let d = maxValue - minValue
        let h: Double
        switch maxValue {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        return h * 60
    }
}
