import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import trufflo

/// A-AC-13: a large photo carrying a position comes out at most 1600 px on
/// its long side, with no location left in it.
@Suite("Photo import")
struct PhotoImportTests {
    private func makeJPEG(width: Int, height: Int, gps: Bool) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "test"]]
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 48.8566, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.3522, kCGImagePropertyGPSLongitudeRef: "E"
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func largePhotoIsResizedAndLosesItsPosition() throws {
        let original = try makeJPEG(width: 4000, height: 3000, gps: true)
        // The fixture really carries a position, or the test proves nothing.
        #expect(try properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let prepared = try #require(PhotoImport.prepare(original))
        let props = try properties(of: prepared)
        let width = try #require(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(props[kCGImagePropertyPixelHeight] as? Int)
        #expect(max(width, height) == 1600)
        #expect(width > height, "le cadrage paysage est conservé")
        #expect(props[kCGImagePropertyGPSDictionary] == nil, "la position doit disparaître")
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifUserComment] == nil, "aucune métadonnée de la source ne survit")
    }

    @Test func smallPhotoIsNotEnlarged() throws {
        let prepared = try #require(PhotoImport.prepare(try makeJPEG(width: 800, height: 600, gps: false)))
        let props = try properties(of: prepared)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 800)
    }

    @Test func notAnImageGivesNothing() {
        #expect(PhotoImport.prepare(Data("pas une image".utf8)) == nil)
    }
}
