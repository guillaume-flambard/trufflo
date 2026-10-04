import Testing
import SwiftUI
@testable import trufflo

@Suite("Theme & Design System Tokens")
struct ThemeTests {
    @Test("Color tokens are accessible")
    func testColorTokens() {
        #expect(TruffloTheme.Colors.forest != nil)
        #expect(TruffloTheme.Colors.sand != nil)
        #expect(TruffloTheme.Colors.peach != nil)
        #expect(Color.truffloForest != nil)
        #expect(Color.truffloSand != nil)
    }

    @Test("Spacing and Radius tokens are valid")
    func testSpacingAndRadius() {
        #expect(TruffloTheme.Spacing.small == 12)
        #expect(TruffloTheme.Spacing.medium == 16)
        #expect(TruffloTheme.Radius.card == 20)
    }
}
