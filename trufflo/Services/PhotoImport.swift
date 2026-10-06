import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares a photo before it is stored on a profile (ART-DIRECTION §2.4, PRD F13).
///
/// The picker hands over the original file: often 12 MB, and carrying the
/// place it was taken in its metadata. What is stored instead is a JPEG at
/// most `maxPixel` on the long side, re-encoded from pixels only, so no EXIF,
/// GPS or maker block survives. The orientation is applied to the pixels
/// rather than kept as a tag, since the tag is dropped with the rest.
enum PhotoImport {
    static let maxPixel = 1600

    /// `nil` when the data is not an image ImageIO can read.
    static func prepare(_ data: Data, maxPixel: Int = maxPixel, quality: Double = 0.85) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        // Only the compression is passed: no properties dictionary from the
        // source, so nothing of its metadata is written back.
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
