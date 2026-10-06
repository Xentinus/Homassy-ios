import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Generates images in-process so no binary fixtures live in the repository.
enum TestImages {
    static func gradient(width: Int, height: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 1),
                      CGColor(red: 0.2, green: 0.35, blue: 0.8, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        return context.makeImage()!
    }

    static func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination), "test image encoding failed")
        return data as Data
    }

    static func jpeg(width: Int, height: Int) -> Data {
        encode(gradient(width: width, height: height), as: .jpeg)
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        let props = properties(of: data)
        guard let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    static func properties(of data: Data) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [:] }
        return props
    }
}
