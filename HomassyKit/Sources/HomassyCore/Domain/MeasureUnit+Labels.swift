import Foundation

extension MeasureUnit {
    /// Units counted in whole things (a piece, a bottle, a spoonful). The consume sheet defaults to 1 for these.
    public var isCountable: Bool {
        switch self {
        case .piece, .teaspoon, .tablespoon, .cup, .pack, .box, .bottle, .can, .jar, .bag: true
        case .gram, .kilogram, .milligram, .milliliter, .centiliter, .deciliter, .liter,
             .meter, .centimeter, .millimeter, .squareMeter, .cubicMeter: false
        }
    }

    /// The abbreviation shown after a number: "kg", "db", "pcs", "Flaschen".
    public func shortLabel(for value: Decimal = 1, locale: Locale = .current) -> String {
        CoreLocalization.format("unit.short.\(rawValue) %lld", locale: locale, Self.pluralCount(for: value))
    }

    /// The spelled-out unit for pickers and VoiceOver: "kilograms", "darab", "Gläser".
    public func name(for value: Decimal = 1, locale: Locale = .current) -> String {
        CoreLocalization.format("unit.name.\(rawValue) %lld", locale: locale, Self.pluralCount(for: value))
    }

    /// The integer handed to the catalog's plural rule. Fractions select `other` in hu, en and de,
    /// so any non-integral value maps to 2.
    static func pluralCount(for value: Decimal) -> Int {
        var source = value.magnitude
        var whole = Decimal()
        NSDecimalRound(&whole, &source, 0, .plain)
        guard whole == value.magnitude, whole <= Decimal(Int.max) else { return 2 }
        return NSDecimalNumber(decimal: whole).intValue
    }
}
