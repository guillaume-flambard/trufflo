import Testing
import SwiftUI
import UIKit
@testable import trufflo

@Suite("Design System Component Tests")
@MainActor
struct ComponentTests {
    @Test("Onboarding steps are properly initialized")
    func testOnboardingSteps() {
        let steps = OnboardingStep.defaultSteps
        #expect(steps.count == 3)
        #expect(steps[0].imageName == "OnboardingWalk")
        #expect(steps[1].imageName == "OnboardingRoutine")
        #expect(steps[2].imageName == "OnboardingCommunity")
    }

    @Test("Every badge style paints an opaque chip")
    func testBadgeStylesPaint() {
        for style in [TruffloBadge.Style.forest, .sage, .peach, .sky, .sand] {
            let badge = TruffloBadge("Chiens", icon: "pawprint", style: style)
            guard let rendered = render(badge) else {
                Issue.record("le badge \(style) ne rend aucune image")
                continue
            }
            #expect(hasVisiblePixels(rendered), "le badge \(style) rend une image transparente")
        }
    }

    @Test("Badge styles are visually distinguishable, not five names for one chip")
    func testBadgeStylesDiffer() {
        let fingerprints = [TruffloBadge.Style.forest, .sage, .peach, .sky, .sand]
            .map { render(TruffloBadge("Chiens", style: $0))?.pngData() }
            .compactMap { $0 }
        #expect(fingerprints.count == 5)
        #expect(Set(fingerprints).count == 5, "deux styles de badge produisent le même rendu")
    }

    @Test("The forest badge is painted with the forest brand colour")
    func testBadgeForestUsesBrandColour() {
        let badge = TruffloBadge("Chiens", style: .forest)
        guard let rendered = render(badge) else {
            Issue.record("le badge forest ne rend aucune image")
            return
        }
        guard let (r, g, b, a) = firstFullyOpaquePixelAlongCenterRow(of: rendered) else {
            Issue.record("aucun pixel opaque dans le badge forest")
            return
        }
        #expect(a == 255, "le fond du badge forest doit être opaque, alpha = \(a)")
        #expect(abs(Int32(r) - 30) <= 2, "red = \(r), attendu 30 (#1E4D3B)")
        #expect(abs(Int32(g) - 77) <= 2, "green = \(g), attendu 77 (#1E4D3B)")
        #expect(abs(Int32(b) - 59) <= 2, "blue = \(b), attendu 59 (#1E4D3B)")
    }

    @Test("Changing the segmented selection changes what is painted")
    func testSegmentedSelectionChangesPainting() {
        let renderings = ["Balades", "Profil"].map { selected in
            render(TruffloSegmentedControl(
                items: ["Balades", "Profil"],
                selection: Binding.constant(selected),
                titleKeyPath: \.self
            ))?.pngData()
        }
        for (index, rendering) in renderings.enumerated() {
            #expect(rendering != nil, "le segmenté n° \(index) ne rend aucune image")
        }
        #expect(renderings[0] != renderings[1],
                "sélectionner « Profil » au lieu de « Balades » ne change pas le rendu")
    }

    @Test("The text field paints its label, its text and a clear affordance")
    func testTextFieldPaintsItsStates() {
        let empty = render(TruffloTextField("Nom", text: Binding.constant("")))
        let filled = render(TruffloTextField("Nom", text: Binding.constant("Oslo")))
        let withError = render(TruffloTextField("Nom",
                                                text: Binding.constant("Oslo"),
                                                errorMessage: "Race requise"))
        #expect(empty != nil)
        #expect(filled != nil)
        #expect(withError != nil)
        #expect(hasVisiblePixels(filled ?? UIImage()), "le champ rempli est transparent")
        #expect(empty?.pngData() != filled?.pngData(),
                "un champ vide et un champ rempli se rendent identiquement")
        #expect(filled?.pngData() != withError?.pngData(),
                "ajouter un message d'erreur ne change pas le rendu du champ")
    }

    // MARK: - Rendering helpers

    private func render<V: View>(_ view: V, width: CGFloat = 320) -> UIImage? {
        ImageRenderer(content: view.frame(width: width)).uiImage
    }

    private func hasVisiblePixels(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        guard let alpha = sample(image, x: cgImage.width / 2, y: cgImage.height / 2)?.3 else {
            return false
        }
        return alpha > 0
    }

    private func firstFullyOpaquePixelAlongCenterRow(of image: UIImage) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard let cgImage = image.cgImage else { return nil }
        let row = cgImage.height / 2
        for x in 0..<cgImage.width {
            guard let pixel = sample(image, x: x, y: row), pixel.3 == 255 else { continue }
            return pixel
        }
        return nil
    }

    private func sample(_ image: UIImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard let cgImage = image.cgImage else { return nil }
        guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { return nil }
        var raw = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &raw,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return (raw[0], raw[1], raw[2], raw[3])
    }
}
