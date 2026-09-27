import Foundation

/// How a store is described under its name (P2-08b, option B, the Apple Maps pattern).
public enum StoreLabel {
    /// "650 m" below a kilometre, "1,2 km" from there.
    public static func distanceText(_ metres: Double, locale: Locale = .current) -> String {
        if metres < 1_000 {
            return Measurement(value: metres.rounded(), unit: UnitLength.meters).formatted(
                .measurement(width: .abbreviated, usage: .asProvided,
                             numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
        }
        return Measurement(value: metres / 1_000, unit: UnitLength.kilometers).formatted(
            .measurement(width: .abbreviated, usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(1))).locale(locale))
    }

    /// "1,2 km · Sport u. 2–4., Budaörs"; whichever part is known; nil when neither is.
    public static func subtitle(address: StoreAddress?, distance: Double?, locale: Locale = .current) -> String? {
        let parts = [distance.map { distanceText($0, locale: locale) }, address?.short].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Auchan · Budaörs", or "Auchan · Sport u. 2–4." when a same-name store shares the locality.
    public static func compact(name: String, address: StoreAddress?, useStreet: Bool) -> String {
        let detail = useStreet ? (address?.street ?? address?.locality) : address?.locality
        guard let detail else { return name }
        return "\(name) · \(detail)"
    }
}
