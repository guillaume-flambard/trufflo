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
    /// Aim the crop at the animal (`FocalCrop`) instead of the middle of the photo:
    /// a portrait photo of a dog has the head high, and a centred square cuts it.
    private let aimsAtAnimal: Bool

    @State private var image: UIImage?
    @State private var focus = FocalCrop.fallbackFocus
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(name: String, photoData: Data?, diameter: CGFloat = 132, aimsAtAnimal: Bool = false) {
        self.name = name
        self.photoData = photoData
        self.diameter = diameter
        self.aimsAtAnimal = aimsAtAnimal
    }

    public var body: some View {
        ZStack {
            if let image, aimsAtAnimal {
                let crop = FocalCrop.layout(imageSize: image.size,
                                            frame: CGSize(width: diameter, height: diameter),
                                            focus: focus)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: crop.size.width, height: crop.size.height)
                    .offset(x: crop.offset.x, y: crop.offset.y)
                    .frame(width: diameter, height: diameter, alignment: .topLeading)
            } else if let image {
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
            // A cover crop needs the short side to reach the frame, so aiming at the
            // animal decodes a little larger than the disc.
            let target = diameter * displayScale * (aimsAtAnimal ? 2 : 1)
            let decoded = photoData.flatMap { Self.downsampled($0, to: target) }
            withAnimation(TruffloTheme.Motion.appear(reduceMotion: reduceMotion)) {
                image = decoded
            }
            guard aimsAtAnimal else { return }
            // Off the main thread: Vision is synchronous.
            focus = await Task.detached(priority: .userInitiated) { [image] in
                image?.cgImage.map(DogFocus.focus(in:)) ?? FocalCrop.fallbackFocus
            }.value
        }
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    /// Decodes at most `maxPixel` on the long side, without ever materialising the
    /// full-size bitmap.
    nonisolated static func downsampled(_ data: Data, to maxPixel: CGFloat) -> UIImage? {
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
