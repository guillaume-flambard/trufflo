import CoreGraphics
import Testing
@testable import trufflo

/// The screen takes its colours from the dog's photo, but the text stays forest,
/// charcoal and slate on top of them. Whatever the photo, that text must stay
/// readable: this is the guarantee, tested on photos of the worst kinds.
@Suite("Dog palette")
struct DogPaletteTests {
    /// Slate, the palest text the screen puts on the tinted area (#5B6472).
    private let slate = DogPalette.RGB(red: 0x5B / 255, green: 0x64 / 255, blue: 0x72 / 255)

    private func solid(_ red: Double, _ green: Double, _ blue: Double, size: Int = 40) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    @Test func contrastRatioFollowsTheWCAGDefinition() {
        let black = DogPalette.RGB(red: 0, green: 0, blue: 0)
        let white = DogPalette.RGB(red: 1, green: 1, blue: 1)
        #expect(abs(black.contrast(with: white) - 21) < 0.01)
        #expect(abs(white.contrast(with: white) - 1) < 0.01)
    }

    @Test func nineColoursAreReturnedInAThreeByThreeGrid() {
        #expect(DogPalette.colors(from: solid(0.8, 0.4, 0.1)).count == 9)
    }

    @Test(arguments: [
        (0.0, 0.0, 0.0),   // a black dog on a dark floor
        (1.0, 0.0, 0.0),   // saturated red
        (0.0, 0.7, 0.0),   // grass
        (0.0, 0.0, 1.0),   // saturated blue
        (0.35, 0.22, 0.1), // brown fur
        (1.0, 1.0, 1.0),   // snow
    ])
    func everyColourKeepsSlateTextReadable(_ red: Double, _ green: Double, _ blue: Double) {
        for colour in DogPalette.colors(from: solid(red, green, blue)) {
            #expect(colour.contrast(with: slate) >= 4.5,
                    "contraste \(colour.contrast(with: slate)) pour un fond tiré de (\(red), \(green), \(blue))")
        }
    }

    @Test func differentPhotosGiveDifferentColours() {
        let warm = DogPalette.colors(from: solid(0.9, 0.5, 0.1))
        let cool = DogPalette.colors(from: solid(0.1, 0.4, 0.9))
        #expect(warm[4].red > warm[4].blue, "un chien roux tire vers le chaud")
        #expect(cool[4].blue > cool[4].red, "un fond bleu tire vers le froid")
    }

    @Test func theColoursStayColourful() {
        // Softening must not turn every photo into the same beige.
        let colour = DogPalette.colors(from: solid(0.9, 0.2, 0.2))[4]
        let spread = max(colour.red, colour.green, colour.blue) - min(colour.red, colour.green, colour.blue)
        #expect(spread > 0.06, "la teinte doit rester lisible, pas devenir un gris")
    }

    @Test func withoutAPhotoTheBrandPaletteIsUsed() {
        #expect(DogPalette.fallback.count == 9)
        for colour in DogPalette.fallback {
            #expect(colour.contrast(with: slate) >= 4.5)
        }
    }
}
