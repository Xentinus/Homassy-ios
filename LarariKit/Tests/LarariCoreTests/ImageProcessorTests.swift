import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LarariCore

@Suite("ImageProcessor")
struct ImageProcessorTests {
    @Test("A 12 MP photo shrinks to 800 px on the long side and stays small")
    func largeLandscape() throws {
        let output = try ImageProcessor.prepare(TestImages.jpeg(width: 4000, height: 3000))
        let size = try #require(TestImages.pixelSize(of: output))
        #expect(size.width == 800)
        #expect(size.height == 600)
        #expect(output.count < 200_000)
    }

    @Test("Small images are not upscaled")
    func smallImage() throws {
        let output = try ImageProcessor.prepare(TestImages.jpeg(width: 300, height: 200))
        let size = try #require(TestImages.pixelSize(of: output))
        #expect(size.width == 300)
        #expect(size.height == 200)
    }

    @Test("Exactly 800 px stays 800 px")
    func exactLimit() throws {
        let output = try ImageProcessor.prepare(TestImages.jpeg(width: 800, height: 800))
        let size = try #require(TestImages.pixelSize(of: output))
        #expect(size.width == 800 && size.height == 800)
    }

    @Test("EXIF orientation is applied to the pixels", arguments: [(400, 300, 300, 400), (4000, 3000, 600, 800)])
    func portraitOrientation(width: Int, height: Int, expectedWidth: Int, expectedHeight: Int) throws {
        // Orientation 6 = "rotate 90° clockwise to display": landscape pixels, portrait photo.
        let input = TestImages.encode(TestImages.gradient(width: width, height: height), as: .jpeg,
                                      properties: [kCGImagePropertyOrientation: 6])
        let output = try ImageProcessor.prepare(input)
        let size = try #require(TestImages.pixelSize(of: output))
        #expect(size.width == expectedWidth)
        #expect(size.height == expectedHeight)
        let orientation = TestImages.properties(of: output)[kCGImagePropertyOrientation] as? Int
        #expect(orientation == nil || orientation == 1)
    }

    @Test("Output is JPEG, whatever the input format")
    func outputIsJPEG() throws {
        let png = TestImages.encode(TestImages.gradient(width: 1200, height: 900), as: .png)
        let output = try ImageProcessor.prepare(png)
        let source = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(output.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test("GPS and camera metadata are stripped")
    func stripsMetadata() throws {
        let input = TestImages.encode(TestImages.gradient(width: 1600, height: 1200), as: .jpeg, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 47.4979, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 19.0402, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCam", kCGImagePropertyTIFFModel: "X1"],
        ])
        #expect(TestImages.properties(of: input)[kCGImagePropertyGPSDictionary] != nil)

        let props = TestImages.properties(of: try ImageProcessor.prepare(input))
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff?[kCGImagePropertyTIFFModel] == nil)
    }

    @Test("Undecodable data throws", arguments: [Data(), Data("definitely not an image".utf8), Data([0xFF, 0xD8, 0xFF, 0x00])])
    func undecodable(data: Data) {
        #expect(throws: ImageProcessor.Failure.undecodable) { try ImageProcessor.prepare(data) }
    }

    @Test("The error message exists in hu, en and de")
    func errorMessage() {
        for id in ["hu_HU", "en_US", "de_DE"] {
            #expect(CoreLocalization.lookup("error.imageUnreadable", locale: Locale(identifier: id)) != nil)
        }
        #expect(ImageProcessor.Failure.undecodable.errorDescription?.isEmpty == false)
    }

    @Test func constants() {
        #expect(ImageProcessor.maxPixel == 800)
        #expect(ImageProcessor.jpegQuality == 0.8)
    }
}
