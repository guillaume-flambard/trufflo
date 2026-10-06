import CoreGraphics
import Testing
@testable import trufflo

/// A phone photo of a dog is portrait and the dog is high in the frame: a
/// centred crop cut its head off (seen on a real photo, 2026-10-07).
@Suite("Focal crop")
struct FocalCropTests {
    // The portrait photo of the test: 1200 x 1600, in a frame about 390 x 370.
    private let photo = CGSize(width: 1200, height: 1600)
    private let frame = CGSize(width: 390, height: 370)

    @Test func theFrameIsAlwaysCoveredAndNeverShowsEmptySpace() {
        for focus in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.2, y: 0.9)] {
            let layout = FocalCrop.layout(imageSize: photo, frame: frame, focus: focus)
            #expect(layout.size.width >= frame.width - 0.001 && layout.size.height >= frame.height - 0.001)
            #expect(layout.offset.x <= 0.001 && layout.offset.y <= 0.001)
            #expect(layout.offset.x + layout.size.width >= frame.width - 0.001)
            #expect(layout.offset.y + layout.size.height >= frame.height - 0.001)
        }
    }

    @Test func aHighFocusKeepsTheTopOfThePhoto() {
        // A dog's head at 20 % from the top: the crop must start near the top.
        let high = FocalCrop.layout(imageSize: photo, frame: frame, focus: CGPoint(x: 0.5, y: 0.2))
        let centred = FocalCrop.layout(imageSize: photo, frame: frame, focus: CGPoint(x: 0.5, y: 0.5))
        #expect(high.offset.y > centred.offset.y, "viser le haut garde plus du haut de la photo")
        // The focus lands inside the visible frame.
        let visibleY = high.offset.y + 0.2 * high.size.height
        #expect(visibleY >= 0 && visibleY <= frame.height)
    }

    @Test func aCentredFocusIsTheOrdinaryFill() {
        let layout = FocalCrop.layout(imageSize: photo, frame: frame, focus: CGPoint(x: 0.5, y: 0.5))
        #expect(abs(layout.offset.y - (frame.height - layout.size.height) / 2) < 0.001)
        #expect(abs(layout.offset.x) < 0.001, "la photo est aussi large que le cadre")
    }

    @Test func aPhotoThatFitsExactlyDoesNotMove() {
        let layout = FocalCrop.layout(imageSize: CGSize(width: 390, height: 370), frame: frame,
                                      focus: CGPoint(x: 0.1, y: 0.9))
        #expect(layout.offset == .zero)
    }

    @Test func aFocusOutsideThePhotoIsClamped() {
        let layout = FocalCrop.layout(imageSize: photo, frame: frame, focus: CGPoint(x: -3, y: 9))
        #expect(layout.offset.y + layout.size.height >= frame.height - 0.001)
    }

    @Test func aDegenerateSizeDoesNotCrash() {
        #expect(FocalCrop.layout(imageSize: .zero, frame: frame, focus: .zero).offset == .zero)
        #expect(FocalCrop.layout(imageSize: photo, frame: .zero, focus: .zero).offset == .zero)
    }

    @Test func visionsLowerLeftBoxBecomesAFocusFromTheTop() {
        // A dog filling the upper-left quarter, in Vision's lower-left coordinates.
        let box = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        let focus = FocalCrop.focus(forAnimalBox: box)
        #expect(abs(focus.x - 0.25) < 0.001)
        #expect(abs(focus.y - 0.15) < 0.001, "le haut de la boîte est à 0, 30 % de sa hauteur plus bas")
        // A dog low in the picture is aimed low.
        let low = FocalCrop.focus(forAnimalBox: CGRect(x: 0.3, y: 0, width: 0.4, height: 0.4))
        #expect(low.y > 0.6)
    }

    @Test func nothingDetectedAimsHighInTheMiddle() {
        #expect(FocalCrop.fallbackFocus == CGPoint(x: 0.5, y: 0.35))
    }
}
