import CoreGraphics
import Foundation

/// Nine soft colours taken from a dog's photo, as a 3 x 3 grid read row by row from
/// the top left: the screen takes the dog's colours the way a now-playing screen
/// takes its cover's.
///
/// The colours are softened until the palest text the screen puts on them (slate,
/// #5B6472) holds 4.5:1, so the photo can be any photo, a black dog on a dark floor
/// included, and the words stay readable. That is the one rule; the rest is taste.
public enum DogPalette {
    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// WCAG 2 relative luminance.
        var luminance: Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }

        /// WCAG 2 contrast ratio, 1 to 21.
        public func contrast(with other: RGB) -> Double {
            let a = luminance, b = other.luminance
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }

        /// Hue in [0, 1).
        var hue: Double {
            let peak = max(red, green, blue), low = min(red, green, blue)
            let chroma = peak - low
            guard chroma > 0 else { return 0 }
            let sector: Double
            switch peak {
            case red: sector = ((green - blue) / chroma).truncatingRemainder(dividingBy: 6)
            case green: sector = (blue - red) / chroma + 2
            default: sector = (red - green) / chroma + 4
            }
            let value = sector / 6
            return value < 0 ? value + 1 : value
        }

        init(hue: Double, saturation: Double, value: Double) {
            let h = (hue - floor(hue)) * 6
            let chroma = value * saturation
            let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
            let m = value - chroma
            let (r, g, b): (Double, Double, Double)
            switch Int(h) {
            case 0: (r, g, b) = (chroma, x, 0)
            case 1: (r, g, b) = (x, chroma, 0)
            case 2: (r, g, b) = (0, chroma, x)
            case 3: (r, g, b) = (0, x, chroma)
            case 4: (r, g, b) = (x, 0, chroma)
            default: (r, g, b) = (chroma, 0, x)
            }
            self.init(red: r + m, green: g + m, blue: b + m)
        }

        func mixed(withWhite amount: Double) -> RGB {
            RGB(red: red + (1 - red) * amount,
                green: green + (1 - green) * amount,
                blue: blue + (1 - blue) * amount)
        }

        /// Pushes the hue of the colour, keeping it, away from grey: the average of a
        /// photo is mostly mud (grass, concrete and fur averaged make a dull beige), and
        /// softening mud gives pale mud. A colour that is really grey (a black dog, snow)
        /// stays grey; any other keeps its hue and gains the saturation of a colour.
        func saturated(by factor: Double, floor minimum: Double = 0.16) -> RGB {
            let peak = max(red, green, blue), low = min(red, green, blue)
            let chroma = peak - low
            guard chroma > 0.02 else { return self }
            // HSB: the hue is kept, the saturation is lifted, the brightness is left alone.
            let saturation = chroma / peak
            let lifted = min(1, max(saturation * factor, minimum))
            let newLow = peak * (1 - lifted)
            func rescale(_ value: Double) -> Double { newLow + (value - low) / chroma * (peak - newLow) }
            return RGB(red: rescale(red), green: rescale(green), blue: rescale(blue))
        }
    }

    /// Slate (#5B6472), the palest text drawn on the tinted area.
    private static let slate = RGB(red: 0x5B / 255, green: 0x64 / 255, blue: 0x72 / 255)
    private static let minimumContrast = 4.6

    /// Used when there is no photo: the brand's mint and sage, softened the same way.
    public static let fallback: [RGB] = [
        RGB(red: 0.84, green: 0.93, blue: 0.89), RGB(red: 0.88, green: 0.95, blue: 0.91), RGB(red: 0.86, green: 0.94, blue: 0.92),
        RGB(red: 0.86, green: 0.94, blue: 0.90), RGB(red: 0.83, green: 0.92, blue: 0.88), RGB(red: 0.88, green: 0.95, blue: 0.92),
        RGB(red: 0.90, green: 0.95, blue: 0.91), RGB(red: 0.87, green: 0.94, blue: 0.90), RGB(red: 0.91, green: 0.95, blue: 0.92),
    ]

    public static func colors(from image: CGImage) -> [RGB] {
        guard let cells = averageCells(of: image) else { return fallback }
        return cells.map { soften($0.saturated(by: 2.2)) }
    }

    /// A pastel of the colour: its hue, a high brightness, and the strongest saturation
    /// that still lets slate text hold the contrast. Mixing with white instead would
    /// lower the saturation and the brightness together and wash every hue into the
    /// same cream; fixing the brightness and spending the contrast budget on the
    /// saturation keeps mint a mint and peach a peach.
    static func soften(_ colour: RGB) -> RGB {
        let peak = max(colour.red, colour.green, colour.blue)
        let chroma = peak - min(colour.red, colour.green, colour.blue)
        guard chroma > 0.02 else {
            // A grey stays grey: a very light one.
            return colour.mixed(withWhite: 0.97)
        }
        let hue = colour.hue
        var saturation = 0.62
        while saturation > 0.03 {
            let candidate = RGB(hue: hue, saturation: saturation, value: 0.98)
            if candidate.contrast(with: slate) >= minimumContrast { return candidate }
            saturation -= 0.02
        }
        return RGB(hue: hue, saturation: 0.03, value: 0.98)
    }

    /// The image reduced to 18 x 18 pixels, then each ninth (6 x 6 pixels) reduced to one
    /// colour by a weighted mean: a vivid pixel weighs far more than a grey one. A plain
    /// average of grass, concrete and wood is a dull beige; weighted, it is the green and
    /// the orange that a person sees in the photo.
    private static func averageCells(of image: CGImage) -> [RGB]? {
        let size = 18, cell = 6, grid = 3
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size,
                                          bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }

        func pixel(_ x: Int, _ y: Int) -> RGB {
            let offset = (y * size + x) * 4
            return RGB(red: Double(pixels[offset]) / 255,
                       green: Double(pixels[offset + 1]) / 255,
                       blue: Double(pixels[offset + 2]) / 255)
        }
        func weight(_ colour: RGB) -> Double {
            let peak = max(colour.red, colour.green, colour.blue)
            let chroma = peak - min(colour.red, colour.green, colour.blue)
            let saturation = peak > 0 ? chroma / peak : 0
            // A small floor, so a truly grey cell still gets an average and not a division by zero.
            return 0.02 + pow(saturation, 2) * (0.35 + peak)
        }
        func mean(of colours: [RGB]) -> RGB {
            let weights = colours.map(weight)
            let total = weights.reduce(0, +)
            return RGB(red: zip(colours, weights).map { $0.red * $1 }.reduce(0, +) / total,
                       green: zip(colours, weights).map { $0.green * $1 }.reduce(0, +) / total,
                       blue: zip(colours, weights).map { $0.blue * $1 }.reduce(0, +) / total)
        }

        // The context's origin is the bottom left; its memory rows run from the top of the
        // image, so row 0 of `pixels` is already the top row.
        let everything = (0..<size).flatMap { y in (0..<size).map { x in pixel(x, y) } }
        let overall = mean(of: everything)
        return (0..<grid * grid).map { index in
            let originX = (index % grid) * cell, originY = (index / grid) * cell
            let inside = (0..<cell).flatMap { dy in (0..<cell).map { dx in pixel(originX + dx, originY + dy) } }
            let local = mean(of: inside)
            // A cell with no colour of its own borrows the photo's overall one, a little.
            let chroma = max(local.red, local.green, local.blue) - min(local.red, local.green, local.blue)
            return chroma < 0.06 ? RGB(red: (local.red + overall.red) / 2,
                                       green: (local.green + overall.green) / 2,
                                       blue: (local.blue + overall.blue) / 2) : local
        }
    }
}
