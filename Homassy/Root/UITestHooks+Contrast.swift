#if DEBUG
import Foundation

extension UITestHooks {
    /// `-uiTestIncreaseContrast`: the scene resolves colours as with Settings ▸ Accessibility ▸ Increase Contrast, so
    /// the accessibility audit checks the high-contrast accent (X-04 1A: Mocha 500 by default, Mocha 800 there).
    static var increasesContrast: Bool { isActive && contains("-uiTestIncreaseContrast") }
}
#endif
