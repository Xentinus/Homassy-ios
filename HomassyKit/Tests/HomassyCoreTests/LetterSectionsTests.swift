import Foundation
import Testing
@testable import HomassyCore

@Suite("LetterSections")
struct LetterSectionsTests {
    static let hu = Locale(identifier: "hu_HU")

    @Test("Keys fold diacritics and send non-letters to #", arguments: [
        ("alma", "A"), ("Áfonya", "A"), ("öntet", "O"), ("Öblítő", "O"), ("  kenyér", "K"), ("123 cola", "#"),
        ("", "#"), ("(bio) tej", "#"), ("🍎 alma", "#"),
    ])
    func keys(name: String, expected: String) {
        #expect(LetterSections.key(for: name, locale: Self.hu) == expected)
    }

    @Test func hashSortsLast() {
        #expect(LetterSections.sortedKeys(["#", "K", "A", "B"]) == ["A", "B", "K", "#"])
    }

    @Test func groupSortsByNameWithinALetter() {
        let groups = LetterSections.group(["banán", "alma", "Áfonya", "1 cola"], locale: Self.hu) { $0 }
        #expect(groups.map(\.key) == ["A", "B", "#"])
        #expect(groups.map(\.values) == [["Áfonya", "alma"], ["banán"], ["1 cola"]])
    }
}
