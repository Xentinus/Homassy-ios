import Testing
@testable import LarariCore

@Suite("MemberColor")
struct MemberColorTests {
    /// (seed, normalised, FNV-1a, preset key). Generated with the web app's memberColors.ts logic under Node 24.
    static let fixtures: [(String, String, UInt32, String)] = [
        ("", "", 2166136261, "indigo"),
        ("a", "a", 3826002220, "sky"),
        ("Larari", "larari", 313717114, "lime"),
        ("_abc123def456", "_abc123def456", 3855220316, "sky"),
        ("3F2504E0-4F89-11D3-9A0C-0305E82C3301", "3f2504e04f8911d39a0c0305e82c3301", 3747917448, "rose"),
        ("3f2504e04f8911d39a0c0305e82c3301", "3f2504e04f8911d39a0c0305e82c3301", 3747917448, "rose"),
        ("00000000-0000-0000-0000-000000000000", "00000000000000000000000000000000", 4039664709, "indigo"),
        ("béla", "béla", 1291137403, "teal"),
        ("Ádám Kovács", "ádám kovács", 2859586447, "fuchsia"),
        ("🙂", "🙂", 2368824094, "violet"),
        ("user-record-name", "userrecordname", 2534553588, "sky"),
    ]

    @Test(arguments: MemberColorTests.fixtures)
    func matchesTheWebApp(fixture: (String, String, UInt32, String)) {
        let (seed, normalised, hash, key) = fixture
        #expect(MemberColor.normalise(seed) == normalised)
        #expect(MemberColor.fnv1a(normalised) == hash)
        #expect(MemberColor.preset(for: seed).key == key)
    }

    @Test func paletteIsFrozen() {
        #expect(MemberColor.presets.map(\.key) == ["rose", "amber", "lime", "teal", "sky", "indigo", "violet", "fuchsia"])
        #expect(MemberColor.presets.map(\.light) == [0xF43F5E, 0xB45309, 0x4D7C0F, 0x0F766E, 0x0369A1, 0x6366F1, 0x8B5CF6, 0xD946EF])
        #expect(MemberColor.presets.map(\.dark) == [0xFB7185, 0xFBBF24, 0xA3E635, 0x2DD4BF, 0x38BDF8, 0x818CF8, 0xA78BFA, 0xE879F9])
        #expect(MemberColor.presets.map(\.gradient.from) == [0xE11D48, 0xD97706, 0x4D7C0F, 0x0D9488, 0x0284C7, 0x4F46E5, 0x7C3AED, 0xC026D3])
        #expect(MemberColor.presets.map(\.gradient.to) == MemberColor.presets.map(\.dark))
    }

    @Test func mochaIsSelectableButNeverPickedByTheHash() {
        #expect(MemberColor.presets.count == 8)
        #expect(!MemberColor.presets.map(\.key).contains("mocha"))
        #expect(MemberColor.selectablePresets.map(\.key)
                == ["rose", "amber", "lime", "teal", "sky", "indigo", "violet", "fuchsia", "mocha"])
        #expect(MemberColor.mocha.key == "mocha")
        #expect(MemberColor.mocha.light == 0x8B7355)
        #expect(MemberColor.mocha.dark == 0xC9B8A0)
        #expect(MemberColor.mocha.gradient.from == 0xA0825B)
        #expect(MemberColor.mocha.gradient.to == 0xC9B8A0)
        for fixture in MemberColorTests.fixtures {
            #expect(MemberColor.preset(for: fixture.0).key != "mocha")
        }
    }

    @Test func presetForKeyResolvesEverySelectableKey() {
        for preset in MemberColor.selectablePresets {
            #expect(MemberColor.preset(forKey: preset.key) == preset)
        }
        #expect(MemberColor.preset(forKey: "custom") == nil)
        #expect(MemberColor.preset(forKey: "") == nil)
    }

    @Test func formattedGuidAndBareGuidGetTheSameColour() {
        #expect(MemberColor.preset(for: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")
                == MemberColor.preset(for: "3f2504e04f8911d39a0c0305e82c3301"))
    }

    /// Hue of each preset's light accent, computed with the web app's hexToHsl.
    @Test(arguments: [("", 238.73239436619718), ("a", 201.26582278481013), ("Larari", 85.87155963302753),
                      ("3F2504E0-4F89-11D3-9A0C-0305E82C3301", 349.72375690607737), ("Ádám Kovács", 292.18934911242604),
                      ("🙂", 258.31168831168833)])
    func hueIsThePresetsLightHue(seed: String, expected: Double) {
        #expect(abs(MemberColor.hue(for: seed) - expected) < 1e-9)
    }

    @Test func hueStaysInRange() {
        for preset in MemberColor.presets {
            let hue = MemberColor.hue(ofHex: preset.light)
            #expect(hue >= 0 && hue < 360)
        }
    }
}
