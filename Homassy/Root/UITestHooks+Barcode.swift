#if DEBUG
import Foundation

extension UITestHooks {
    /// `-uiTestScannedBarcode <code>`: the scanner sheet delivers `<code>` at once instead of opening the camera.
    /// Only honoured in UI-test launches (`-uiTestAccountState` present).
    static var scannedBarcode: String? {
        guard isActive else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiTestScannedBarcode"), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}
#endif
