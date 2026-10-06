import SwiftUI

/// How strongly a glass surface is tinted forest. The surfaces that carry numbers
/// need the stronger tint to stay readable over bright streets and pale parkland.
/// Native glass tints more transparently than a flat fill, hence the higher values.
public enum TruffloGlassStrength {
    case soft
    case strong

    var tintOpacity: Double {
        switch self {
        case .soft: return 0.45
        case .strong: return 0.70
        }
    }
}

/// The glass language of the walk screens: Apple's Liquid Glass, tinted forest,
/// never used for content.
///
/// Content in this app stays on warm opaque surfaces. Glass marks controls and
/// measurements that float over the map, which is the only thing behind them.
///
/// The material is the system one (`glassEffect`), so it refracts, adapts to the
/// content behind it and reacts like every other iOS 27 control. The forest tint
/// is what keeps white figures readable over bright streets and pale parkland.
///
/// Under Reduce Transparency the surface is an opaque forest instead. The system
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
                .background(TruffloTheme.Colors.forestDeep, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        } else {
            content
                .glassEffect(.regular.tint(Color.truffloForestDeep.opacity(strength.tintOpacity))
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