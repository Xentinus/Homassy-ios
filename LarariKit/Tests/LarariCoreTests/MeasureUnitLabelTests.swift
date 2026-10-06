import Foundation
import Testing
@testable import LarariCore

@Suite("MeasureUnit labels")
struct MeasureUnitLabelTests {
    static let hu = Locale(identifier: "hu_HU")
    static let en = Locale(identifier: "en_US")
    static let de = Locale(identifier: "de_DE")

    @Test("Every unit has a short label and a name in hu, en and de, singular and plural")
    func catalogIsComplete() {
        for locale in [Self.hu, Self.en, Self.de] {
            for unit in MeasureUnit.allCases {
                #expect(CoreLocalization.lookup("unit.short.\(unit.rawValue) %lld", locale: locale) != nil,
                        "missing short label \(unit) in \(locale.identifier)")
                #expect(CoreLocalization.lookup("unit.name.\(unit.rawValue) %lld", locale: locale) != nil,
                        "missing name \(unit) in \(locale.identifier)")
                for value in [Decimal(1), Decimal(2)] {
                    let short = unit.shortLabel(for: value, locale: locale)
                    let name = unit.name(for: value, locale: locale)
                    #expect(!short.isEmpty && !short.contains("unit.") && !short.contains("%"))
                    #expect(!name.isEmpty && !name.contains("unit.") && !name.contains("%"))
                }
            }
        }
    }

    @Test("Short labels match the web app", arguments: [
        (MeasureUnit.piece, "hu_HU", "db"), (.piece, "en_US", "pc"), (.piece, "de_DE", "Stk"),
        (.kilogram, "hu_HU", "kg"), (.deciliter, "de_DE", "dl"), (.squareMeter, "en_US", "m²"),
        (.teaspoon, "hu_HU", "kk"), (.tablespoon, "de_DE", "EL"), (.jar, "hu_HU", "befőttes"),
        (.bag, "de_DE", "Beutel"), (.bottle, "en_US", "bottle"),
    ])
    func shortSingular(unit: MeasureUnit, localeID: String, expected: String) {
        #expect(unit.shortLabel(for: 1, locale: Locale(identifier: localeID)) == expected)
    }

    @Test("Plural variants", arguments: [
        (MeasureUnit.piece, "en_US", "2", "pcs"), (.cup, "en_US", "1.5", "cups"), (.box, "en_US", "3", "boxes"),
        (.bottle, "de_DE", "2", "Flaschen"), (.jar, "de_DE", "2", "Gläser"), (.cup, "de_DE", "2", "Tassen"),
        (.piece, "hu_HU", "2", "db"), (.pack, "hu_HU", "5", "csomag"), (.kilogram, "en_US", "2", "kg"),
        (.cup, "en_US", "0", "cups"),
    ])
    func shortPlural(unit: MeasureUnit, localeID: String, value: String, expected: String) {
        let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
        #expect(unit.shortLabel(for: decimal, locale: Locale(identifier: localeID)) == expected)
    }

    @Test("Full names", arguments: [
        (MeasureUnit.kilogram, "en_US", "1", "kilogram"), (.kilogram, "en_US", "2", "kilograms"),
        (.kilogram, "hu_HU", "2", "kilogramm"), (.piece, "hu_HU", "1", "darab"),
        (.piece, "de_DE", "2", "Stück"), (.jar, "de_DE", "2", "Gläser"),
        (.squareMeter, "en_US", "2", "square meters"), (.liter, "en_US", "0.5", "liters"),
    ])
    func names(unit: MeasureUnit, localeID: String, value: String, expected: String) {
        let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
        #expect(unit.name(for: decimal, locale: Locale(identifier: localeID)) == expected)
    }

    @Test func pluralCountSelection() {
        #expect(MeasureUnit.pluralCount(for: 1) == 1)
        #expect(MeasureUnit.pluralCount(for: 0) == 0)
        #expect(MeasureUnit.pluralCount(for: 7) == 7)
        #expect(MeasureUnit.pluralCount(for: Decimal(string: "1.5")!) == 2)
        #expect(MeasureUnit.pluralCount(for: Decimal(string: "0.25")!) == 2)
    }

    @Test func countableUnits() {
        #expect(MeasureUnit.piece.isCountable)
        #expect(MeasureUnit.bottle.isCountable)
        #expect(!MeasureUnit.gram.isCountable)
        #expect(!MeasureUnit.liter.isCountable)
    }

    @Test("Unsupported languages fall back to English")
    func fallback() {
        #expect(MeasureUnit.piece.shortLabel(for: 2, locale: Locale(identifier: "fr_FR")) == "pcs")
    }
}
