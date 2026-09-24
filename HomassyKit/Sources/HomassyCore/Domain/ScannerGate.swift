import Foundation

/// Mirrors `AVAuthorizationStatus` raw values so HomassyCore needs no AVFoundation import.
public enum CameraAuthorization: Int, Sendable {
    case notDetermined = 0, restricted = 1, denied = 2, authorized = 3
}

extension CameraAuthorization {
    public init(rawStatus: Int) { self = CameraAuthorization(rawValue: rawStatus) ?? .denied }
}

public enum ScannerGateState: Equatable, Sendable {
    case ready, needsPermission, denied, restricted, unsupported, unavailable
}

public enum ScannerGate {
    /// `isSupported` / `isAvailable` are `DataScannerViewController`'s class properties. `isAvailable`
    /// is also false without camera permission, so permission is checked first.
    public static func state(authorization: CameraAuthorization, isSupported: Bool, isAvailable: Bool) -> ScannerGateState {
        guard isSupported else { return .unsupported }
        switch authorization {
        case .notDetermined: return .needsPermission
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return isAvailable ? .ready : .unavailable
        }
    }
}
