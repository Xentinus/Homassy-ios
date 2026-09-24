import Foundation
import Testing
@testable import HomassyCore

@Suite("ServiceError")
struct ServiceErrorTests {
    static let all: [ServiceError] = [.nameRequired, .quantityMustBePositive, .quantityExceedsStock, .expiryBeforePurchase, .readOnlySpace, .notFound, .invalidURL]

    @Test("Every error has a message in hu, en and de", arguments: ["hu_HU", "en_US", "de_DE"])
    func translated(localeID: String) {
        for error in Self.all {
            let message = CoreLocalization.lookup(error.catalogKey, locale: Locale(identifier: localeID))
            #expect(message?.isEmpty == false, "\(error) missing in \(localeID)")
        }
    }

    @Test func descriptions() {
        for error in Self.all {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.errorDescription != error.catalogKey)
        }
        #expect(CoreLocalization.string("error.nameRequired", locale: Locale(identifier: "hu_HU")) == "A név megadása kötelező.")
    }

    @Test func undoTitleTranslated() {
        for id in ["hu_HU", "en_US", "de_DE"] {
            #expect(CoreLocalization.lookup("undo.item.delete %@", locale: Locale(identifier: id)) != nil)
        }
        #expect(CoreLocalization.format("undo.item.delete %@", locale: Locale(identifier: "en_US"), "Milk") == "Milk removed")
    }
}
