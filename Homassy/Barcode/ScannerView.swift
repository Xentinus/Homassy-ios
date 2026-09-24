import HomassyCore
import SwiftUI
import Vision
import VisionKit

/// DataScannerViewController for EAN-13, EAN-8, UPC-E and Code 128.
/// Uses `ScannedSymbology` (HomassyCore's `BarcodeSymbology`): the iOS 27 SDK's Vision has a type with the same name.
struct ScannerView: UIViewControllerRepresentable {
    /// The torch is switched here, next to the scanner, so a stalled scan session can be restarted right after.
    var torchOn = false
    let onScan: (String, ScannedSymbology) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if !controller.isScanning { try? controller.startScanning() }
        if context.coordinator.torchOn != torchOn {
            context.coordinator.torchOn = torchOn
            Torch.set(torchOn)
            // Reconfiguring the camera can stop the session; restart it if so.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if !controller.isScanning { try? controller.startScanning() }
            }
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        if coordinator.torchOn { Torch.set(false) }
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String, ScannedSymbology) -> Void
        var torchOn = false

        init(onScan: @escaping (String, ScannedSymbology) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue else { continue }
                onScan(payload, Self.symbology(barcode.observation.symbology))
                return
            }
        }

        static func symbology(_ value: VNBarcodeSymbology) -> ScannedSymbology {
            switch value {
            case .ean13: .ean13
            case .ean8: .ean8
            case .upce: .upce
            case .code128: .code128
            default: .other
            }
        }
    }
}
