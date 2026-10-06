import AVFoundation

/// The back camera's torch, for scanning barcodes in a dark pantry. DataScannerViewController has no torch API of
/// its own, so this drives the capture device while the scanner runs.
///
/// The first version locked the plain wide-angle camera; on a device whose scanner session runs on a virtual
/// (dual-wide or triple) camera that froze the preview (user report, 2026-09-24). The torch now goes through the
/// same virtual device the camera system picks first.
enum Torch {
    static var isAvailable: Bool { device.map { $0.hasTorch && $0.isTorchAvailable } ?? false }

    static func set(_ isOn: Bool) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if isOn {
            try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
        } else if device.torchMode != .off {
            device.torchMode = .off
        }
    }

    private static var device: AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video, position: .back
        ).devices.first
    }
}
