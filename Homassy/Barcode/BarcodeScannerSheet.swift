import AVFoundation
import HomassyCore
import SwiftUI
import VisionKit

struct BarcodeScannerSheet: View {
    let onScan: (String, ScannedSymbology) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var gate: ScannerGateState = .needsPermission
    @State private var delivered = false
    @State private var torchOn = false

    var body: some View {
        NavigationStack {
            Group {
                switch gate {
                case .ready:
                    ScannerView { code, symbology in deliver(code, symbology) }
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) {
                            Text("barcode.hint")
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.bottom, 32)
                        }
                case .needsPermission:
                    explanation("barcode.permission.message", symbol: "camera") {
                        Button("barcode.permission.allow") { Task { await requestAccess() } }
                            .buttonStyle(.borderedProminent)
                    }
                case .denied:
                    explanation("barcode.denied.message", symbol: "camera.fill") {
                        Button("barcode.openSettings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                case .restricted:
                    explanation("barcode.restricted.message", symbol: "lock") { EmptyView() }
                case .unsupported:
                    explanation("barcode.unsupported.message", symbol: "barcode.viewfinder") { EmptyView() }
                case .unavailable:
                    explanation("barcode.unavailable.message", symbol: "exclamationmark.triangle") {
                        Button("barcode.retry") { refreshGate() }
                    }
                }
            }
            .navigationTitle("barcode.scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.close") { dismiss() } }
                if gate == .ready, Torch.isAvailable {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            torchOn.toggle()
                            Torch.set(torchOn)
                        } label: {
                            Label(torchOn ? "barcode.torch.off" : "barcode.torch.on",
                                  systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        }
                        .accessibilityIdentifier("barcode.torch")
                    }
                }
            }
            .onDisappear { if torchOn { Torch.set(false) } }
        }
        .task {
            #if DEBUG
            if let code = UITestHooks.scannedBarcode {
                try? await Task.sleep(for: .milliseconds(600))    // let the sheet finish presenting first
                deliver(code, .other)
                return
            }
            #endif
            refreshGate()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshGate()                                         // back from Settings
        }
    }

    private func explanation<Actions: View>(_ message: LocalizedStringKey, symbol: String,
                                            @ViewBuilder action: () -> Actions) -> some View {
        ContentUnavailableView {
            Label("barcode.permission.title", systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            action()
        }
    }

    private func refreshGate() {
        #if DEBUG
        guard UITestHooks.scannedBarcode == nil else { return }
        #endif
        gate = ScannerGate.state(
            authorization: CameraAuthorization(rawStatus: AVCaptureDevice.authorizationStatus(for: .video).rawValue),
            isSupported: DataScannerViewController.isSupported,
            isAvailable: DataScannerViewController.isAvailable)
    }

    private func requestAccess() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        refreshGate()
    }

    private func deliver(_ code: String, _ symbology: ScannedSymbology) {
        guard !delivered else { return }
        delivered = true
        if torchOn { Torch.set(false); torchOn = false }
        onScan(code, symbology)                                   // the flow steps on in the same sheet
    }
}
