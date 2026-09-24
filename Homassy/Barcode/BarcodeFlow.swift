import HomassyCore
import SwiftUI

/// HomassyCore's `BarcodeSymbology`, named so for files that import Vision or VisionKit: the iOS 27 SDK has a
/// `BarcodeSymbology` too, and the module name cannot disambiguate because HomassyCore has an enum of that name.
typealias ScannedSymbology = BarcodeSymbology

/// The whole scan flow in one sheet that steps in place: scanner → action sheet (known) or product form (unknown)
/// → stock form. Chaining separate sheets (presenting the next one from the previous one's `onDismiss`) left the
/// action sheet stuck on screen, so the steps are views inside a single presentation.
private struct BarcodeFlowSheet: View {
    enum Step: Equatable {
        case scanning
        case actions(UUID, String)
        case addStock(UUID)
        case createProduct(String)
    }

    let space: Space?
    let onCheckStock: (UUID) -> Void

    @Environment(ServiceContainer.self) private var services
    @State private var step: Step = .scanning
    @State private var scanModel: BarcodeScanModel?

    var body: some View {
        switch step {
        case .scanning:
            BarcodeScannerSheet { code, symbology in handle(code, symbology) }
        case .actions(let id, let name):
            BarcodeActionSheet(productName: name, canEdit: space.map(services.products.canEdit) ?? false,
                               onAddToInventory: { step = .addStock(id) },
                               onCheckStock: { onCheckStock(id) })
        case .addStock(let id):
            if let space {
                StockFormSheet(model: StockFormModel(mode: .add(space, productID: id), inventory: services.inventory,
                                                     products: services.products, storage: services.storageLocations))
            }
        case .createProduct(let code):
            if let space {
                ProductFormSheet(model: ProductFormModel(mode: .create(space, barcode: code), service: services.products))
            }
        }
    }

    /// One scan session per presentation: `BarcodeScanModel` ignores repeated recognitions of a code in frame.
    private func handle(_ code: String, _ symbology: BarcodeSymbology) {
        if scanModel == nil, let space {
            scanModel = BarcodeScanModel(router: BarcodeRouter(products: services.products), space: space)
        }
        switch scanModel?.handle(code, symbology: symbology) {
        case .known(let id, let name): step = .actions(id, name)
        case .unknown(let barcode): step = .createProduct(barcode)
        case nil: break
        }
    }
}

/// Presents the scan flow and, for "Check stock", pushes the product detail onto the tab's navigation stack
/// after the sheet has closed (so the detail keeps the tab's undo toast). Apply inside a NavigationStack.
private struct BarcodeFlowModifier: ViewModifier {
    @Binding var isScanning: Bool
    let space: Space?

    @State private var pendingRoute: ProductRoute?
    @State private var detailRoute: ProductRoute?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isScanning, onDismiss: { detailRoute = pendingRoute; pendingRoute = nil }) {
                BarcodeFlowSheet(space: space) { id in
                    pendingRoute = ProductRoute(id: id)
                    isScanning = false
                }
            }
            .navigationDestination(item: $detailRoute) { ProductDetailView(productID: $0.id) }
    }
}

extension View {
    func barcodeFlow(isScanning: Binding<Bool>, space: Space?) -> some View {
        modifier(BarcodeFlowModifier(isScanning: isScanning, space: space))
    }
}
