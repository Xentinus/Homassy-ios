import Foundation

/// Splits a paid total across lots in proportion to their amounts (P2-08a), so every lot has the same unit
/// price. Each share is rounded to 2 decimals and the last share takes the rest, so the shares always add up
/// to the total.
public enum ProportionalSplit {
    public static func split(total: Decimal, weights: [Decimal]) -> [Decimal] {
        guard !weights.isEmpty else { return [] }
        let sum = weights.reduce(0, +)
        // Unreachable through the services, which reject lots of 0.
        guard sum > 0 else { return weights.map { _ in 0 } }
        var shares: [Decimal] = []
        var assigned: Decimal = 0
        for weight in weights.dropLast() {
            var raw = total * weight / sum
            var rounded = Decimal()
            NSDecimalRound(&rounded, &raw, 2, .plain)
            shares.append(rounded)
            assigned += rounded
        }
        shares.append(total - assigned)
        return shares
    }

    /// "450 Ft + 450 Ft": the shares as currency amounts, for the price footer.
    public static func text(total: Decimal, weights: [Decimal], currency: String, locale: Locale) -> String {
        split(total: total, weights: weights)
            .map { $0.formatted(.currency(code: currency).locale(locale)) }
            .joined(separator: " + ")
    }
}
