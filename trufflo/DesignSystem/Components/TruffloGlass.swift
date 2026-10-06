import SwiftUI

/// How strongly a glass surface is tinted forest. The surfaces that carry numbers
/// need the stronger tint to stay readable over bright streets and pale parkland.
public enum TruffloGlassStrength {
    case soft
    case strong

    var tintOpacity: Double {
        switch self {
        case .soft: return 0.20
        case .strong: return 0.34
        }
    }
}

/// The glass language of the walk screens: a blurred, forest-tinted surface with a
/// light rim, never used for content.
///
/// Content in this app stays on warm opaque surfaces. Glass marks controls and
/// measurements that float over the map, which is the only thing behind them.
///
/// Under Reduce Transparency the material is replaced by an opaque forest. A
/// blurred surface is not legible against map tiles, so falling back to a
/// translucent tint would make the measurements unreadable for exactly the people
/// who asked for the setting.
///
/// The rim has to be stroked on a concrete shape, because an opaque `some Shape`
/// exposes no `stroke` of its own. Hence one helper per shape rather than a shape
/// parameter.
struct TruffloGlass<S: InsettableShape>: ViewModifier {
    var strength: TruffloGlassStrength = .soft
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Weaker under Reduce Transparency: the surface is opaque there, so a bright
    /// highlight would only read as leftover decoration.
    private var rimOpacity: Double { reduceTransparency ? 0.18 : 0.38 }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(TruffloTheme.Colors.forestDeep, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(rimOpacity), lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Color.truffloForestDeep.opacity(strength.tintOpacity), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(rimOpacity), lineWidth: 1))
                .shadow(color: Color.truffloForestDeep.opacity(0.16), radius: 20, y: 6)
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
    func truffloGlassCircle(strength: TruffloGlassStrength = .soft) -> some View {
        modifier(TruffloGlass(strength: strength, shape: Circle()))
    }

    /// Glass on a control-shaped surface, for buttons that sit beside each other.
    func truffloGlassControl(strength: TruffloGlassStrength = .soft) -> some View {
        modifier(TruffloGlass(strength: strength,
                              shape: RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium,
                                                      style: .continuous)))
    }
}