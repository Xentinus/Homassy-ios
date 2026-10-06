import Foundation
import Testing
@testable import LarariCore

@Suite("String catalog")
struct StringCatalogTests {
    /// The source catalog, read from the repository: the compiled bundle holds .strings files, not the JSON.
    static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()                    // LarariCoreTests
        .deletingLastPathComponent()                    // Tests
        .deletingLastPathComponent()                    // LarariKit
        .appending(path: "Sources/LarariCore/Resources/Localizable.xcstrings")

    static func catalog() throws -> [String: Any] {
        let data = try Data(contentsOf: catalogURL)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func entries() throws -> [String: [String: Any]] {
        try #require(try catalog()["strings"] as? [String: [String: Any]])
    }

    @Test func sourceLanguageIsEnglish() throws {
        #expect(try Self.catalog()["sourceLanguage"] as? String == "en")
    }

    @Test func catalogIsNotEmpty() throws {
        #expect(try !Self.entries().isEmpty)
    }

    @Test func everyKeyHasEnglishHungarianAndGerman() throws {
        var missing: [String] = []
        for (key, entry) in try Self.entries() {
            if entry["shouldTranslate"] as? Bool == false { continue }
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in LarariCoreResources.languages where !Self.hasValue(localizations[language]) {
                missing.append("\(key) [\(language)]")
            }
        }
        #expect(missing.isEmpty, "Missing translations: \(missing.sorted().joined(separator: ", "))")
    }

    @Test func compiledBundleHasEveryLanguage() {
        let localizations = LarariCoreResources.bundle.localizations
        for language in LarariCoreResources.languages {
            #expect(localizations.contains(language), "No \(language).lproj in the resource bundle")
        }
    }

    @Test func compiledBundleResolvesEveryKeyInEveryLanguage() throws {
        let sentinel = "\u{1}MISSING"
        var missing: [String] = []
        for language in LarariCoreResources.languages {
            let path = try #require(LarariCoreResources.bundle.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            for key in try Self.entries().keys {
                if bundle.localizedString(forKey: key, value: sentinel, table: nil) == sentinel {
                    missing.append("\(key) [\(language)]")
                }
            }
        }
        #expect(missing.isEmpty, "Not compiled: \(missing.sorted().joined(separator: ", "))")
    }

    private static func hasValue(_ localization: [String: Any]?) -> Bool {
        guard let localization else { return false }
        if let unit = localization["stringUnit"] as? [String: Any] {
            return !((unit["value"] as? String) ?? "").isEmpty
        }
        return localization["variations"] != nil
    }
}
