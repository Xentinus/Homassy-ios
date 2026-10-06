import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LarariCore

/// The product photo editor's image work (user request, 2026-09-24): rotate by quarter turns, crop a square,
/// store small (≤ 800 px, JPEG 0.8, no metadata).
@Suite("ImageProcessor crop and rotate")
struct ImageCropTests {
    /// Left half red, right half blue.
    static func halves(width: Int, height: Int) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return TestImages.encode(context.makeImage()!, as: .png)
    }

    /// The colour at a point measured from the top-left, as "red", "blue" or "other".
    static func colour(of data: Data, x: Int, y: Int) -> String {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        let (r, b) = (Int(pixel[0]), Int(pixel[2]))
        if r > 180 && b < 80 { return "red" }
        if b > 180 && r < 80 { return "blue" }
        return "other"
    }

    @Test func editableCopyIsOrientedAndBounded() throws {
        let input = TestImages.encode(TestImages.gradient(width: 4000, height: 3000), as: .jpeg,
                                      properties: [kCGImagePropertyOrientation: 6])
        let size = try #require(TestImages.pixelSize(of: try ImageProcessor.editable(input)))
        #expect(size.width == 1536 && size.height == 2048)
    }

    @Test func cropsASquare() throws {
        let output = try ImageProcessor.crop(Self.halves(width: 400, height: 300),
                                             to: CGRect(x: 0.125, y: 0, width: 0.75, height: 1), quarterTurns: 0)
        let size = try #require(TestImages.pixelSize(of: output))
        #expect(size.width == 300 && size.height == 300)
        #expect(Self.colour(of: output, x: 20, y: 150) == "red")
        #expect(Self.colour(of: output, x: 280, y: 150) == "blue")
        #expect(output.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test("A quarter turn is counter-clockwise: the left edge ends up at the bottom")
    func rotatesCounterClockwise() throws {
        let output = try ImageProcessor.crop(Self.halves(width: 200, height: 100),
                                             to: CGRect(x: 0, y: 0, width: 1, height: 1), quarterTurns: 1)
        let size = try #require(TestImages.pixelSize(of: output))
        #expect(size.width == 100 && size.height == 200)
        #expect(Self.colour(of: output, x: 50, y: 20) == "blue")
        #expect(Self.colour(of: output, x: 50, y: 180) == "red")
    }

    @Test("Three quarter turns equal one clockwise turn", arguments: [3, -1])
    func rotatesClockwise(turns: Int) throws {
        let output = try ImageProcessor.crop(Self.halves(width: 200, height: 100),
                                             to: CGRect(x: 0, y: 0, width: 1, height: 1), quarterTurns: turns)
        #expect(Self.colour(of: output, x: 50, y: 20) == "red")
        #expect(Self.colour(of: output, x: 50, y: 180) == "blue")
    }

    @Test func croppedPhotosStaySmall() throws {
        let output = try ImageProcessor.crop(TestImages.jpeg(width: 4000, height: 3000),
                                             to: CGRect(x: 0.125, y: 0, width: 0.75, height: 1), quarterTurns: 0)
        let size = try #require(TestImages.pixelSize(of: output))
        #expect(size.width == 800 && size.height == 800)
        #expect(output.count < 200_000)
    }

    @Test func rectsOutsideTheImageAreClamped() throws {
        let output = try ImageProcessor.crop(Self.halves(width: 400, height: 300),
                                             to: CGRect(x: -0.2, y: -0.1, width: 2, height: 2), quarterTurns: 0)
        let size = try #require(TestImages.pixelSize(of: output))
        #expect(size.width == 400 && size.height == 300)
    }

    @Test func garbageThrows() {
        #expect(throws: ImageProcessor.Failure.undecodable) {
            try ImageProcessor.crop(Data("nope".utf8), to: CGRect(x: 0, y: 0, width: 1, height: 1), quarterTurns: 0)
        }
        #expect(throws: ImageProcessor.Failure.undecodable) { try ImageProcessor.editable(Data()) }
    }
}
