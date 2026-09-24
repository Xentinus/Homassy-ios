import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares product photos for storage: ≤ 800 px, orientation baked in, JPEG 0.8, no metadata.
public enum ImageProcessor {
    public static let maxPixel = 800
    public static let jpegQuality = 0.8

    public enum Failure: Error, Equatable, LocalizedError {
        case undecodable
        case encodingFailed

        public var errorDescription: String? {
            String(localized: "error.imageUnreadable", bundle: .module)
        }
    }

    /// Pure and nonisolated; callers on the main actor should run it in a detached task.
    public static func prepare(_ data: Data) throws -> Data {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { throw Failure.undecodable }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixel),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw Failure.undecodable
        }

        // A fresh destination fed a bare CGImage carries no EXIF, GPS or TIFF data from the source.
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData,
                                                                 UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.encodingFailed }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return output as Data
    }

    // MARK: Photo editor (user request, 2026-09-24)

    /// The photo editor's working copy: orientation baked in, longest side at most `maxPixel`, JPEG 0.9.
    /// Keeps a camera photo's memory small while the user crops and rotates it.
    public static func editable(_ data: Data, maxPixel: Int = 2048) throws -> Data {
        try encode(try orientedImage(data, maxPixel: maxPixel), quality: 0.9)
    }

    /// Rotates by `quarterTurns` × 90° counter-clockwise, crops `rect` (unit coordinates of the rotated image,
    /// origin top-left, clamped to the image), then stores it like any product photo: ≤ 800 px, JPEG 0.8, no metadata.
    public static func crop(_ data: Data, to rect: CGRect, quarterTurns: Int) throws -> Data {
        let image = try orientedImage(data, maxPixel: nil)
        let rotated = try rotate(image, quarterTurns: quarterTurns)
        let unit = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !unit.isNull, unit.width > 0, unit.height > 0 else { throw Failure.undecodable }
        let width = CGFloat(rotated.width), height = CGFloat(rotated.height)
        let pixels = CGRect(x: unit.minX * width, y: unit.minY * height,
                            width: unit.width * width, height: unit.height * height).integral
        guard let cropped = rotated.cropping(to: pixels) else { throw Failure.encodingFailed }
        return try prepare(try encode(cropped, quality: 0.95))
    }

    /// Decodes with the EXIF orientation applied, optionally downsampled so the longest side is at most `maxPixel`.
    private static func orientedImage(_ data: Data, maxPixel: Int?) throws -> CGImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { throw Failure.undecodable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixel ?? Int.max),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.undecodable
        }
        return image
    }

    private static func rotate(_ image: CGImage, quarterTurns: Int) throws -> CGImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }
        let (width, height) = (image.width, image.height)
        let (newWidth, newHeight) = turns % 2 == 0 ? (width, height) : (height, width)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: newWidth, height: newHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.encodingFailed }
        // Core Graphics is y-up, so a positive angle turns the picture counter-clockwise as seen on screen.
        context.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
        context.rotate(by: CGFloat(turns) * .pi / 2)
        context.draw(image, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2,
                                       width: CGFloat(width), height: CGFloat(height)))
        guard let rotated = context.makeImage() else { throw Failure.encodingFailed }
        return rotated
    }

    private static func encode(_ image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData,
                                                                 UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.encodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return output as Data
    }
}
