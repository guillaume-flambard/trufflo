import SwiftUI
import ImageIO

/// A dog's face: the photo when there is one, otherwise a sage field carrying the
/// first letter of the name.
///
/// The photo is optional (PRD F01), so the fallback is designed rather than left
/// as a hole, and it is deliberately not a paw print: `DESIGN-SYSTEM.md` rules out
/// repeated paw decoration.
///
/// The photo is decoded down to the displayed size. The stored data is whatever
/// the system picker handed over, and decoding a multi-megapixel image to fill a
/// 132 pt disc would cost memory and scroll time for nothing.
public struct TruffloDogPortrait: View {
    private let name: String
    private let photoData: Data?
    private let diameter: CGFloat

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    public init(name: String, photoData: Data?, diameter: CGFloat = 132) {
        self.name = name
        self.photoData = photoData
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Opaque, so the initial stays readable on any background,
                // forest chips included.
                Color(red: 0.83, green: 0.92, blue: 0.88)
                Text(initial)
                    .font(.system(size: diameter * 0.46, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.truffloForest)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(image == nil ? "Portrait de \(name)" : "Photo de \(name)")
        .task(id: photoData) {
            image = photoData.flatMap { Self.downsampled($0, to: diameter * displayScale) }
        }
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    /// Decodes at most `maxPixel` on the long side, without ever materialising the
    /// full-size bitmap.
    static func downsampled(_ data: Data, to maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map(UIImage.init(cgImage:))
    }
}
