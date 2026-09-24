import Foundation
import Observation

/// Turns the scanner's stream of recognitions into one routed outcome.
@MainActor
@Observable
public final class BarcodeScanModel {
    public enum Outcome: Equatable, Sendable {
        case known(productID: UUID, name: String)
        case unknown(barcode: String)
    }

    public let space: Space
    public private(set) var outcome: Outcome?
    public private(set) var errorMessage: String?
    private let router: BarcodeRouter

    public init(router: BarcodeRouter, space: Space) {
        self.router = router
        self.space = space
    }

    /// DataScanner keeps reporting while the code stays in frame; only the first one counts.
    public func handle(_ raw: String, symbology: BarcodeSymbology) -> Outcome? {
        guard outcome == nil, raw.nilIfBlank != nil else { return nil }
        do {
            switch try router.route(barcode: raw, symbology: symbology, in: space) {
            case .known(let product): outcome = .known(productID: product.publicId, name: product.name)
            case .unknown(let code): outcome = .unknown(barcode: code)
            }
            return outcome
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func reset() {
        outcome = nil
        errorMessage = nil
    }
}
