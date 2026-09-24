import Testing
@testable import HomassyCore

@Suite("ScannerGate")
struct ScannerGateTests {
    @Test("Permission and availability map to one state", arguments: [
        (CameraAuthorization.authorized, true, true, ScannerGateState.ready),
        (.authorized, true, false, .unavailable),
        (.notDetermined, true, false, .needsPermission),
        (.denied, true, false, .denied),
        (.restricted, true, false, .restricted),
        (.authorized, false, false, .unsupported),
        (.denied, false, false, .unsupported),
    ])
    func mapping(authorization: CameraAuthorization, supported: Bool, available: Bool, expected: ScannerGateState) {
        #expect(ScannerGate.state(authorization: authorization, isSupported: supported, isAvailable: available) == expected)
    }

    @Test("Raw AVAuthorizationStatus values", arguments: [(0, CameraAuthorization.notDetermined), (1, .restricted),
                                                           (2, .denied), (3, .authorized), (42, .denied)])
    func rawStatus(raw: Int, expected: CameraAuthorization) {
        #expect(CameraAuthorization(rawStatus: raw) == expected)
    }
}
