#if DEBUG
import Foundation

extension UITestHooks {
    /// `-uiTestSeed`: fixture data (UITestSeed). Only honoured under `-uiTestAccountState`, i.e. the in-memory store.
    static var isSeeded: Bool { isActive && contains("-uiTestSeed") }
}
#endif
