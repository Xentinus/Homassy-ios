import Foundation
import Testing
@testable import LarariCore

@Suite("Quantity")
struct QuantityTests {
    static let nbsp = "\u{00A0}"
    static func d(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    @Test("Format uses the locale separator, trims zeros and joins with a no-break space", arguments: [
        ("1.5", MeasureUnit.kilogram, "hu_HU", "1,5\u{00A0}kg"),
        ("1.5", .kilogram, "en_US", "1.5\u{00A0}kg"),
        ("1.5", .kilogram, "de_DE", "1,5\u{00A0}kg"),
        ("2", .piece, "hu_HU", "2\u{00A0}db"),
        ("1", .piece, "en_US", "1\u{00A0}pc"),
        ("2", .piece, "en_US", "2\u{00A0}pcs"),
        ("2", .bottle, "de_DE", "2\u{00A0}Flaschen"),
        ("1.5", .cup, "en_US", "1.5\u{00A0}cups"),
        ("2.500", .liter, "en_US", "2.5\u{00A0}l"),
        ("0.3333333", .liter, "en_US", "0.333\u{00A0}l"),
        ("0.0005", .liter, "en_US", "0.001\u{00A0}l"),
        ("1.0004", .cup, "en_US", "1\u{00A0}cup"),
        ("1234.5", .gram, "en_US", "1234.5\u{00A0}g"),
        ("1234.5", .gram, "hu_HU", "1234,5\u{00A0}g"),
        ("0", .pack, "de_DE", "0\u{00A0}Packungen"),
    ])
    func format(value: String, unit: MeasureUnit, localeID: String, expected: String) {
        #expect(Quantity.format(Self.d(value), unit: unit, locale: Locale(identifier: localeID)) == expected)
    }

    @Test("Parse accepts plain decimals", arguments: [
        ("1,5", "hu_HU", "1.5"), ("1.5", "hu_HU", "1.5"), ("1,5", "de_DE", "1.5"), ("1.5", "de_DE", "1.5"),
        ("1.5", "en_US", "1.5"), (" 2 ", "en_US", "2"), ("0", "en_US", "0"), ("0,125", "de_DE", "0.125"),
        ("10", "hu_HU", "10"), ("007", "en_US", "7"), ("2.50", "en_US", "2.5"),
    ])
    func parseValid(text: String, localeID: String, expected: String) {
        #expect(Quantity.parse(text, locale: Locale(identifier: localeID)) == Self.d(expected))
    }

    @Test("Parse rejects negatives, grouping and garbage", arguments: [
        ("-1", "en_US"), ("-1,5", "hu_HU"), ("+2", "en_US"), ("abc", "en_US"), ("", "hu_HU"), ("   ", "de_DE"),
        ("1.2.3", "en_US"), ("1,2,3", "hu_HU"), ("1,5", "en_US"), ("1,000", "en_US"), ("1 000", "hu_HU"),
        ("1.000,5", "de_DE"), (",5", "hu_HU"), ("1,", "hu_HU"), (".5", "en_US"), ("1e3", "en_US"),
        ("١٢", "en_US"), ("2 kg", "en_US"),
    ])
    func parseInvalid(text: String, localeID: String) {
        #expect(Quantity.parse(text, locale: Locale(identifier: localeID)) == nil)
    }

    @Test("Formatted numbers parse back", arguments: ["hu_HU", "en_US", "de_DE"])
    func roundTrip(localeID: String) {
        let locale = Locale(identifier: localeID)
        for text in ["0", "1", "1.5", "0.25", "12.125", "999"] {
            let value = Self.d(text)
            #expect(Quantity.parse(Quantity.formatNumber(value, locale: locale), locale: locale) == value)
        }
    }
}
