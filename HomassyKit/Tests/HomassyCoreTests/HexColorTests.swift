import Testing
@testable import HomassyCore

@Suite("HexColor")
struct HexColorTests {
    @Test func splitsIntoChannels() {
        let c = HexColor.components(0xB8956A)
        #expect(c.r == 0xB8)
        #expect(c.g == 0x95)
        #expect(c.b == 0x6A)
    }

    @Test func ignoresBitsAboveTwentyFour() {
        let c = HexColor.components(0xFF00_0000 | 0x123456)
        #expect(c.r == 0x12 && c.g == 0x34 && c.b == 0x56)
    }

    @Test(arguments: [("#b8956a", UInt32(0xB8956A)), ("#B8956A", 0xB8956A), ("#000000", 0), ("#ffffff", 0xFFFFFF)])
    func parsesStrictSixDigitHex(input: String, expected: UInt32) {
        #expect(HexColor.parse(input) == expected)
    }

    @Test(arguments: ["", "#fff", "b8956a", "#b8956", "#b8956a0", "#b8956a00", "#gg0000", " #b8956a", "rgb(1,2,3)", "#+12345"])
    func rejectsEverythingElse(input: String) {
        #expect(HexColor.parse(input) == nil)
    }

    @Test func formatsLowerCase() {
        #expect(HexColor.format(0xB8956A) == "#b8956a")
        #expect(HexColor.format(0x00000F) == "#00000f")
    }
}
