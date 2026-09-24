#if DEBUG
import UIKit

extension UITestHooks {
    /// `-uiTestSamplePhoto`: "Choose photo" opens the photo editor with a generated 1200 × 900 picture
    /// instead of the system photo picker. Only honoured in UI-test launches.
    static var samplePhoto: Data? {
        guard isActive, contains("-uiTestSamplePhoto") else { return nil }
        let size = CGSize(width: 1200, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: size.width / 2, height: size.height)))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}
#endif
