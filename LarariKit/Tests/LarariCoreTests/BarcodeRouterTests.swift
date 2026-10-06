import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("BarcodeRouter")
struct BarcodeRouterTests {
    @Test("Normalisation", arguments: [
        ("5991234567890", BarcodeSymbology.ean13, "5991234567890"),
        (" 5991234567890\n", .other, "5991234567890"),
        ("5991-2345 67890", .other, "5991234567890"),
        ("012345678905", .other, "0012345678905"),
        ("01234565", .upce, "0012345000065"),
        ("96385074", .ean8, "96385074"),
        ("96385074", .other, "96385074"),
        ("ABC-123 x", .code128, "ABC-123 x"),
    ])
    func normalize(raw: String, symbology: BarcodeSymbology, expected: String) {
        #expect(BarcodeRouter.normalize(raw, symbology: symbology) == expected)
    }

    @Test("UPC-E expansion covers every last-digit rule", arguments: [
        ("01234505", "012000003455"),     // d6 in 0...2
        ("01234531", "012300000451"),     // d6 == 3
        ("01234543", "012340000053"),     // d6 == 4
        ("01234565", "012345000065"),     // d6 in 5...9
    ])
    func expandUPCE(upce: String, upca: String) {
        #expect(BarcodeRouter.expandUPCE(upce) == upca)
    }

    @Test("Invalid UPC-E", arguments: ["1234567", "21234565", "0123456A", ""])
    func invalidUPCE(code: String) {
        #expect(BarcodeRouter.expandUPCE(code) == nil)
    }

    @Test func candidatesIncludeTheUPCAForm() {
        #expect(BarcodeRouter.candidates(for: "0012345678905") == ["0012345678905", "012345678905"])
        #expect(BarcodeRouter.candidates(for: "012345678905") == ["0012345678905", "012345678905"])
        #expect(BarcodeRouter.candidates(for: "5991234567890") == ["5991234567890"])
        #expect(BarcodeRouter.candidates(for: " 5991-234567890 ") == ["5991234567890", "5991-234567890"])
    }

    @Test func routesKnownAndUnknown() async throws {
        let env = try ServiceTestEnvironment()
        let home = try env.makeHousehold()
        let milk = try await env.makeProduct("Milk", barcode: "5991234567890")
        let chips = try await env.makeProduct("Chips", barcode: "012345678905")          // stored as UPC-A
        try await env.makeProduct("Other", in: home, barcode: "4000000000009")
        let router = BarcodeRouter(products: env.productService())

        #expect(try router.route(barcode: "5991234567890", symbology: .ean13, in: env.personal) == .known(milk))
        #expect(try router.route(barcode: "0012345678905", symbology: .ean13, in: env.personal) == .known(chips))
        #expect(try router.route(barcode: "012345678905", in: env.personal) == .known(chips))
        #expect(try router.route(barcode: "4000000000009", in: env.personal) == .unknown("4000000000009"))
        #expect(try router.route(barcode: "01234565", symbology: .upce, in: env.personal) == .unknown("0012345000065"))
    }

    @Test func scanModelIgnoresRepeatsUntilReset() async throws {
        let env = try ServiceTestEnvironment()
        let milk = try await env.makeProduct("Milk", barcode: "5991234567890")
        let model = BarcodeScanModel(router: BarcodeRouter(products: env.productService()), space: env.personal)
        #expect(model.handle("   ", symbology: .other) == nil)
        #expect(model.handle("5991234567890", symbology: .ean13) == .known(productID: milk.publicId, name: "Milk"))
        #expect(model.handle("4000000000009", symbology: .ean13) == nil)
        #expect(model.outcome == .known(productID: milk.publicId, name: "Milk"))
        model.reset()
        #expect(model.handle("4000000000009", symbology: .ean13) == .unknown(barcode: "4000000000009"))
    }
}
