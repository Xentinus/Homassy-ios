import Foundation

/// Looks up LarariCore catalog strings for an explicit locale.
///
/// `String(localized:bundle:)` always follows the app's current language. Formatters that take a
/// `Locale` argument (and the tests that pin hu/en/de output) need the language of *that* locale,
/// so they resolve the matching `.lproj` inside the package's resource bundle directly.
enum CoreLocalization {
    static let supportedLanguages = ["en", "hu", "de"]

    static func bundle(for locale: Locale) -> Bundle {
        let code = locale.language.languageCode?.identifier ?? "en"
        let language = supportedLanguages.contains(code) ? code : "en"
        if let url = Bundle.module.url(forResource: language, withExtension: "lproj"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }

    /// The translated string, or `nil` when the key is missing for that language.
    static func lookup(_ key: String, locale: Locale) -> String? {
        let missing = "\u{1}missing\u{1}"
        let value = bundle(for: locale).localizedString(forKey: key, value: missing, table: "Localizable")
        return value == missing ? nil : value
    }

    static func string(_ key: String, locale: Locale) -> String {
        lookup(key, locale: locale) ?? key
    }

    /// Formats a catalog string (plain or plural-varying) with `locale`'s plural rules and digits.
    static func format(_ key: String, locale: Locale, _ arguments: any CVarArg...) -> String {
        String(format: string(key, locale: locale), locale: locale, arguments: arguments)
    }
}
