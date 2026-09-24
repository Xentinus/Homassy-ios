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
}
