import Testing
@testable import HomassyCore

@Suite("Shopping list palette")
struct ShoppingListPaletteTests {
    @Test func parsesHex() throws {
        let rgb = try #require(ShoppingListPalette.rgb("#E0A458"))
        #expect(abs(rgb.red - 224.0 / 255) < 0.0001)
        #expect(abs(rgb.green - 164.0 / 255) < 0.0001)
        #expect(abs(rgb.blue - 88.0 / 255) < 0.0001)
        #expect(ShoppingListPalette.rgb("e0a458") != nil)
        #expect(ShoppingListPalette.rgb("#E0A4") == nil)
        #expect(ShoppingListPalette.rgb("#GGGGGG") == nil)
    }

    @Test func everyPaletteColourParses() {
        #expect(ShoppingListPalette.colors.count == 8)
        #expect(ShoppingListPalette.colors.allSatisfy { ShoppingListPalette.rgb($0) != nil })
    }

    @Test func customColoursAreAnyHexOutsideThePalette() {
        #expect(ShoppingListPalette.isCustom("#123456"))
        #expect(!ShoppingListPalette.isCustom("#e0a458"))
        #expect(!ShoppingListPalette.isCustom(nil))
        #expect(!ShoppingListPalette.isCustom("zzz"))
    }
}
