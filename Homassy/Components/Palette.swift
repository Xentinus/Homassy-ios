import HomassyCore
import SwiftUI
import UIKit

extension Color {
    /// `0xRRGGBB` in sRGB.
    init(hex: UInt32) {
        let c = HexColor.components(hex)
        self.init(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, opacity: 1)
    }
}

extension MemberColorPreset {
    /// The member accent for the current appearance. Use for rings, borders and dots only.
    func accent(for scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? dark : light)
    }
}

extension Color {
    /// The member accent for `seed` (a member's `colorSeed`, or a user record name), adapting to light and dark
    /// without needing the colour scheme. The one helper every member ring, border and dot uses (P5-03, P5-04).
    static func memberAccent(seed: String) -> Color {
        let preset = MemberColor.preset(for: seed)
        return Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? preset.dark : preset.light))
        })
    }
}

/// Mocha scale from the web app's main.css, plus the semantic colours from the asset catalogue.
enum Palette {
    static let mocha50 = Color(hex: 0xF5F0EB)
    static let mocha100 = Color(hex: 0xEFE9E0)
    static let mocha200 = Color(hex: 0xE0D5C7)
    static let mocha300 = Color(hex: 0xD4C7B5)
    static let mocha400 = Color(hex: 0xC9B8A0)
    static let mocha500 = Color(hex: 0xB8956A)
    static let mocha600 = Color(hex: 0xA0825B)
    static let mocha700 = Color(hex: 0x8B7355)
    static let mocha800 = Color(hex: 0x6F5A44)
    static let mocha900 = Color(hex: 0x5A4536)
    static let mocha950 = Color(hex: 0x3F3027)

    static let accent = Color.accentColor
    static let expirySoon = Color.expirySoon
    static let expiryCritical = Color.expiryCritical
    static let memberRingFallback = Color.memberRingFallback
}

#if DEBUG
private struct PaletteSwatches: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            Section("Mocha") {
                ForEach(Array(zip(["50", "100", "200", "300", "400", "500", "600", "700", "800", "900", "950"],
                                  [Palette.mocha50, Palette.mocha100, Palette.mocha200, Palette.mocha300, Palette.mocha400,
                                   Palette.mocha500, Palette.mocha600, Palette.mocha700, Palette.mocha800, Palette.mocha900,
                                   Palette.mocha950])), id: \.0) { name, color in
                    Label { Text(verbatim: name) } icon: { Circle().fill(color) }
                }
            }
            Section("Semantic") {
                Label { Text(verbatim: "Accent") } icon: { Circle().fill(Palette.accent) }
                Label { Text(verbatim: "Expiry soon") } icon: { Circle().fill(Palette.expirySoon) }
                Label { Text(verbatim: "Expiry critical") } icon: { Circle().fill(Palette.expiryCritical) }
                Label { Text(verbatim: "Member fallback") } icon: { Circle().strokeBorder(Palette.memberRingFallback, lineWidth: 3) }
            }
            Section("Members") {
                ForEach(MemberColor.selectablePresets, id: \.key) { preset in
                    Label { Text(verbatim: preset.key) } icon: { Circle().strokeBorder(preset.accent(for: scheme), lineWidth: 3) }
                }
                Label { Text(verbatim: "memberAccent(seed: \"_abc123\")") } icon: {
                    Circle().strokeBorder(Color.memberAccent(seed: "_abc123"), lineWidth: 3)
                }
            }
        }
    }
}

#Preview("Light") { PaletteSwatches() }
#Preview("Dark") { PaletteSwatches().preferredColorScheme(.dark) }
#endif
