import SwiftUI

/// How much sand the glass carries. The surfaces that carry numbers need more of
/// it to keep forest figures readable over a busy street map.
public enum TruffloGlassStrength {
    case soft
    case strong

    var tintOpacity: Double {
        switch self {
        case .soft: return 0.25
        case .strong: return 0.55
        }
    }
}

/// The glass language of the walk screens: Apple's Liquid Glass, light and tinted
/// sand, never used for content.
///
/// Light, like every other control of the app (tab bar, toolbar buttons). The walk
/// screen used to be a dark forest glass with white words, and moving from Today to
/// the live walk felt like going from day to night (2026-10-07 review). The figures
/// are now forest on pale glass, the same ink as everywhere else.
///
/// Content in this app stays on warm opaque surfaces. Glass marks controls and
/// measurements that float over the map, which is the only thing behind them.
///
/// The material is the system one (`glassEffect`), so it refracts, adapts to the
/// content behind it and reacts like every other iOS 27 control. The forest tint
/// is what keeps forest figures readable over a busy street map.
///
/// Under Reduce Transparency the surface is an opaque sand instead. The system
/// already tones glass down for that setting; an explicit opaque fallback is kept
/// because a blurred surface over map tiles is the case where measurements stop
/// being legible for exactly the people who asked for the setting.
struct TruffloGlass<S: InsettableShape>: ViewModifier {
    var strength: TruffloGlassStrength = .soft
    var interactive = false
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color.truffloSand, in: shape)
                .overlay(shape.strokeBorder(Color.truffloForest.opacity(0.14), lineWidth: 1))
        } else {
            content
                .glassEffect(.regular.tint(Color.truffloSand.opacity(strength.tintOpacity))
                                .interactive(interactive),
                             in: shape)
        }
    }
}

extension View {
    /// Glass on a card-shaped surface.
    func truffloGlass(strength: TruffloGlassStrength = .soft) -> some View {
        modifier(TruffloGlass(strength: strength,
                              shape: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card,
                                                      style: .continuous)))
    }

    /// Glass on a pill, for the measurements.
    func truffloGlassCapsule(strength: TruffloGlassStrength = .soft) -> some View {
        modifier(TruffloGlass(strength: strength, shape: Capsule()))
    }

    /// Glass on a circle, for the round controls.
    func truffloGlassCircle(strength: TruffloGlassStrength = .soft,
                            interactive: Bool = false) -> some View {
        modifier(TruffloGlass(strength: strength, interactive: interactive, shape: Circle()))
    }

    /// Glass on a control-shaped surface, for buttons that sit beside each other.
    func truffloGlassControl(strength: TruffloGlassStrength = .soft,
                             interactive: Bool = false) -> some View {
        modifier(TruffloGlass(strength: strength, interactive: interactive,
                              shape: RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium,
                                                      style: .continuous)))
    }
}