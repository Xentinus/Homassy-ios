import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("StorageColor")
struct StorageColorTests {
    @Test("Stored values round-trip", arguments: [
        ("blue", StorageColor.blue), ("gray", .gray), ("#4a90d9", .custom(0x4A90D9)), ("#000000", .custom(0)),
    ])
    func roundTrip(stored: String, expected: StorageColor) {
        #expect(StorageColor(rawValue: stored) == expected)
        #expect(expected.rawValue == stored)
    }

    @Test("Hex from the web app is accepted in either case and stored lowercase")
    func webHex() {
        #expect(StorageColor(rawValue: "#4A90D9") == .custom(0x4A90D9))
        #expect(StorageColor.custom(0x4A90D9).rawValue == "#4a90d9")
    }

    @Test("Unknown values are rejected", arguments: ["", "Blue", "magenta", "#12345", "#1234567", "4a90d9", "#gg0000"])
    func unknown(stored: String) {
        #expect(StorageColor(rawValue: stored) == nil)
    }

    @Test func paletteIsTheEightPresets() {
        #expect(StorageColor.palette == [.red, .orange, .yellow, .green, .teal, .blue, .purple, .gray])
        #expect(StorageColor.palette.allSatisfy { !$0.isCustom })
        #expect(StorageColor.custom(0x123456).isCustom)
    }

    @Test("Every colour has a translated name", arguments: ["hu_HU", "en_US", "de_DE"])
    func names(localeID: String) {
        for color in StorageColor.palette {
            #expect(CoreLocalization.lookup("storageColor.\(color.rawValue)", locale: Locale(identifier: localeID)) != nil)
        }
        #expect(CoreLocalization.lookup("storageColor.custom", locale: Locale(identifier: localeID)) != nil)
        #expect(!StorageColor.custom(0x123456).localizedName.isEmpty)
    }

    @Test func customColourIsStoredAsHex() throws {
        let env = try ServiceTestEnvironment()
        let service = env.storageService()
        let cellar = try service.create(in: env.personal, name: "Cellar", color: .custom(0x8B7355), isFreezer: false)
        #expect(cellar.color == "#8b7355")
        #expect(cellar.storageColor == .custom(0x8B7355))

        let form = StorageLocationFormModel(mode: .edit(cellar), service: service)
        #expect(form.color == .custom(0x8B7355))
        form.color = .custom(0x336699)
        #expect(form.save())
        #expect(cellar.color == "#336699")
    }
}
