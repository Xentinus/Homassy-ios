import Foundation

public enum Quantity {
    public static let maximumFractionDigits = 3

    /// "1,5 kg" in Hungarian, "1.5 kg" in English. Number and label are joined with U+00A0.
    public static func format(_ value: Decimal, unit: MeasureUnit, locale: Locale) -> String {
        let rounded = round(value)
        return "\(formatNumber(rounded, locale: locale))\u{00A0}\(unit.shortLabel(for: rounded, locale: locale))"
    }

    /// The number alone: locale separator, at most three fraction digits, no trailing zeros, no grouping.
    public static func formatNumber(_ value: Decimal, locale: Locale) -> String {
        round(value).formatted(
            .number
                .locale(locale)
                .grouping(.never)
                .precision(.fractionLength(0...maximumFractionDigits))
        )
    }

    /// Strict, non-negative parse. See the task's rules; returns nil for anything else.
    public static func parse(_ text: String, locale: Locale) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let localeSeparator = locale.decimalSeparator.flatMap { $0.count == 1 ? Character($0) : nil } ?? "."
        var separators: Set<Character> = [localeSeparator]
        if localeSeparator == "," { separators.insert(".") }

        var whole = ""
        var fraction = ""
        var sawSeparator = false
        for character in trimmed {
            if character.isASCII, character.isWholeNumber {
                if sawSeparator { fraction.append(character) } else { whole.append(character) }
            } else if separators.contains(character), !sawSeparator {
                sawSeparator = true
            } else {
                return nil
            }
        }
        guard !whole.isEmpty, !sawSeparator || !fraction.isEmpty else { return nil }
        let canonical = sawSeparator ? "\(whole).\(fraction)" : whole
        return Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func round(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, maximumFractionDigits, .plain)
        return result
    }
}
