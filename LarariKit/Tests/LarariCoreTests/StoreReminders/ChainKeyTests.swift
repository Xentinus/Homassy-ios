import Testing
@testable import LarariCore

@Suite("ChainKey")
struct ChainKeyTests {
    @Test func takesTheFirstWordLowercasedWithoutDiacritics() {
        #expect(ChainKey.make("Auchan Budaörs") == "auchan")
        #expect(ChainKey.make("AUCHAN Csömör") == "auchan")
        #expect(ChainKey.make("SPAR Market") == "spar")
        #expect(ChainKey.make("  Lidl ") == "lidl")
        #expect(ChainKey.make("Príma") == "prima")
    }

    @Test func keepsKnownMultiWordBrands() {
        #expect(ChainKey.make("Tesco Expressz Óbuda") == "tesco expressz")
        #expect(ChainKey.make("CBA Príma Pasarét") == "cba prima")
        #expect(ChainKey.make("Tesco Hipermarket") == "tesco")
    }

    @Test func punctuationSplitsWords() {
        #expect(ChainKey.make("dm-drogerie markt") == "dm")
        #expect(ChainKey.make("Penny, Váci út") == "penny")
    }

    @Test func emptyForNoLetters() {
        #expect(ChainKey.make("  ") == "")
        #expect(ChainKey.make("—") == "")
    }

    @Test func displayNameUsesTheMostCommonSpelling() {
        #expect(ChainKey.displayName(of: ["Auchan Budaörs", "Auchan Csömör", "AUCHAN"]) == "Auchan")
        #expect(ChainKey.displayName(of: ["Tesco Expressz Óbuda"]) == "Tesco Expressz")
        #expect(ChainKey.displayName(of: []) == "")
    }
}
