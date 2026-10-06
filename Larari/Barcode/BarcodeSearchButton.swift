import LarariCore
import SwiftUI

/// A toolbar button that scans one barcode and hands it to a search (user request, 2026-09-24).
struct BarcodeSearchButton: View {
    let identifier: String
    let onScan: (String, BarcodeSymbology) -> Void

    @State private var scanning = false

    var body: some View {
        Button { scanning = true } label: { Label("search.byBarcode", systemImage: "barcode.viewfinder") }
            .accessibilityIdentifier(identifier)
            .sheet(isPresented: $scanning) {
                BarcodeScannerSheet { code, symbology in
                    scanning = false
                    onScan(code, symbology)
                }
            }
    }
}
