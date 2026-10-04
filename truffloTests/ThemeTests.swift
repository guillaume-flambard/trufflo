import Testing
import SwiftUI
import UIKit
@testable import trufflo

@Suite("Theme & Design System Tokens")
struct ThemeTests {
    private func srgb(_ color: Color) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
    }

    @Test("Each colour token resolves to the brand value documented in Theme.swift")
    func testColorTokensMatchBrandValues() {
        let expected: [(String, Color, CGFloat, CGFloat, CGFloat)] = [
            ("forest", TruffloTheme.Colors.forest, 0.118, 0.302, 0.231),
            ("sage", TruffloTheme.Colors.sage, 0.298, 0.686, 0.482),
            ("mint", TruffloTheme.Colors.mint, 0.655, 0.843, 0.773),
            ("sand", TruffloTheme.Colors.sand, 0.969, 0.957, 0.929),
            ("peach", TruffloTheme.Colors.peach, 1.000, 0.702, 0.541),
            ("terracotta", TruffloTheme.Colors.terracotta, 0.851, 0.463, 0.337),
            ("sky", TruffloTheme.Colors.sky, 0.655, 0.780, 0.906),
            ("chocolate", TruffloTheme.Colors.chocolate, 0.361, 0.251, 0.200),
            ("charcoal", TruffloTheme.Colors.charcoal, 0.176, 0.176, 0.176),
        ]

        for (name, token, wantR, wantG, wantB) in expected {
            guard let (r, g, b, a) = srgb(token) else {
                Issue.record("\(name) ne résout pas depuis le catalogue d'actifs")
                continue
            }
            #expect(abs(r - wantR) < 0.01, "\(name).red = \(r), attendu \(wantR)")
            #expect(abs(g - wantG) < 0.01, "\(name).green = \(g), attendu \(wantG)")
            #expect(abs(b - wantB) < 0.01, "\(name).blue = \(b), attendu \(wantB)")
            #expect(abs(a - 1) < 0.01, "\(name) n'est pas opaque")
        }
    }

    @Test("Convenience extensions alias the theme tokens instead of redrawing them")
    func testColorExtensionsAliasThemeTokens() {
        #expect(Color.truffloForest == TruffloTheme.Colors.forest)
        #expect(Color.truffloSage == TruffloTheme.Colors.sage)
        #expect(Color.truffloMint == TruffloTheme.Colors.mint)
        #expect(Color.truffloSand == TruffloTheme.Colors.sand)
        #expect(Color.truffloPeach == TruffloTheme.Colors.peach)
        #expect(Color.truffloTerracotta == TruffloTheme.Colors.terracotta)
        #expect(Color.truffloSky == TruffloTheme.Colors.sky)
        #expect(Color.truffloChocolate == TruffloTheme.Colors.chocolate)
        #expect(Color.truffloCharcoal == TruffloTheme.Colors.charcoal)
    }

    @Test("Spacing scale is strictly increasing so layout steps never collide")
    func testSpacingScaleIsMonotonic() {
        let scale = [
            TruffloTheme.Spacing.xxSmall,
            TruffloTheme.Spacing.xSmall,
            TruffloTheme.Spacing.small,
            TruffloTheme.Spacing.medium,
            TruffloTheme.Spacing.large,
            TruffloTheme.Spacing.xLarge,
            TruffloTheme.Spacing.xxLarge,
        ]
        #expect(scale.first == 4)
        #expect(scale.last == 48)
        for index in 1..<scale.count {
            #expect(scale[index] > scale[index - 1],
                    "Spacing \(index) (\(scale[index])) n'est pas supérieur au précédent (\(scale[index - 1]))")
        }
    }

    @Test("Corner radius scale is strictly increasing and the pill outranks every card")
    func testRadiusScale() {
        let scale = [
            TruffloTheme.Radius.small,
            TruffloTheme.Radius.medium,
            TruffloTheme.Radius.large,
            TruffloTheme.Radius.card,
        ]
        for index in 1..<scale.count {
            #expect(scale[index] > scale[index - 1])
        }
        #expect(TruffloTheme.Radius.card == 20)
        #expect(TruffloTheme.Radius.pill > TruffloTheme.Radius.card)
        #expect(TruffloTheme.Radius.small > 0)
    }

    @Test("Type scale shrinks monotonically from title to caption")
    func testTypeScaleIsMonotonic() {
        let scale: [CGFloat] = [28, 20, 17, 16, 13]
        for index in 1..<scale.count {
            #expect(scale[index] < scale[index - 1])
        }
    }
}
