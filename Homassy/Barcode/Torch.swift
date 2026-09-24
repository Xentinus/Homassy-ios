import AVFoundation

/// The back camera's torch, for scanning barcodes in a dark pantry. DataScannerViewController has no torch API of
/// its own, so this drives the same capture device while the scanner runs.
enum Torch {
    static var isAvailable: Bool { device?.hasTorch == true && device?.isTorchAvailable == true }

    static func set(_ isOn: Bool) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if isOn {
            try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
        } else {
            device.torchMode = .off
        }
    }

    private static var device: AVCaptureDevice? { AVCaptureDevice.default(for: .video) }
}
