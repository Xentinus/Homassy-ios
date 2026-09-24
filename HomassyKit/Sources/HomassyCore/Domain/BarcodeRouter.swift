import Foundation

public enum BarcodeSymbology: String, Sendable, CaseIterable { case ean13, ean8, upce, code128, other }

public enum BarcodeRoute: Equatable {
    case known(Product)
    case unknown(String)
}

/// Routes a scanned code against the active space's own catalogue (spec §6.6).
@MainActor
public struct BarcodeRouter {
    private let products: ProductService

    public init(products: ProductService) {
        self.products = products
    }

    public func route(barcode: String, symbology: BarcodeSymbology = .other, in space: Space) throws -> BarcodeRoute {
        for candidate in Self.candidates(for: barcode, symbology: symbology) {
            if let product = try products.product(barcode: candidate, in: space) { return .known(product) }
        }
        return .unknown(Self.normalize(barcode, symbology: symbology))
    }

    public nonisolated static func normalize(_ raw: String, symbology: BarcodeSymbology = .other) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators: Set<Character> = [" ", "-"]
        guard !trimmed.isEmpty, trimmed.allSatisfy({ ($0.isASCII && $0.isWholeNumber) || separators.contains($0) })
        else { return trimmed }
        let digits = trimmed.filter { $0.isASCII && $0.isWholeNumber }

        if symbology == .upce, let upca = expandUPCE(digits) { return "0" + upca }
        if digits.count == 12 { return "0" + digits }
        return digits
    }

    public nonisolated static func candidates(for raw: String, symbology: BarcodeSymbology = .other) -> [String] {
        let normalized = normalize(raw, symbology: symbology)
        var result = [normalized]
        if normalized.count == 13, normalized.hasPrefix("0"), normalized.allSatisfy(\.isWholeNumber) {
            result.append(String(normalized.dropFirst()))
        }
        result.append(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        var seen = Set<String>()
        return result.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// UPC-E (number system 0 or 1, six digits, check digit) → UPC-A. The check digit carries over.
    public nonisolated static func expandUPCE(_ code: String) -> String? {
        let digits = Array(code)
        guard digits.count == 8, digits.allSatisfy({ $0.isASCII && $0.isWholeNumber }),
              digits[0] == "0" || digits[0] == "1" else { return nil }
        let system = digits[0]
        let d = digits[1...6].map(String.init)
        let check = String(digits[7])
        let body: String
        switch d[5] {
        case "0", "1", "2": body = d[0] + d[1] + d[5] + "0000" + d[2] + d[3] + d[4]
        case "3": body = d[0] + d[1] + d[2] + "00000" + d[3] + d[4]
        case "4": body = d[0] + d[1] + d[2] + d[3] + "00000" + d[4]
        default: body = d[0] + d[1] + d[2] + d[3] + d[4] + "0000" + d[5]
        }
        return String(system) + body + check
    }
}
