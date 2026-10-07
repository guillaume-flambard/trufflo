import SwiftUI

public struct TruffloButtonStyle: ButtonStyle {
    public enum Variant {
        case primary
        case secondary
        case outline
        case ghost
    }

    public let variant: Variant
    public let isFullWidth: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(variant: Variant = .primary, isFullWidth: Bool = true) {
        self.variant = variant
        self.isFullWidth = isFullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.truffloHeadline)
            .padding(.vertical, TruffloTheme.Spacing.small)
            .padding(.horizontal, TruffloTheme.Spacing.large)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: variant == .outline ? 1.5 : 0)
            )
            .scaleEffect(configuration.isPressed ? TruffloTheme.Motion.pressScale : 1.0)
            .animation(TruffloTheme.Motion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, isPressed in isPressed }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return isPressed ? Color.truffloForest.opacity(0.85) : Color.truffloForest
        case .secondary:
            return isPressed ? Color.truffloSage.opacity(0.85) : Color.truffloSage
        case .outline:
            return isPressed ? Color.truffloSand : Color.clear
        case .ghost:
            return isPressed ? Color.truffloMint.opacity(0.4) : Color.clear
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return .white
        case .secondary:
            return Color.truffloForest
        case .outline, .ghost:
            return Color.truffloForest
        }
    }

    private var borderColor: Color {
        switch variant {
        case .outline:
            return Color.truffloForest
        default:
            return .clear
        }
    }
}

public extension ButtonStyle where Self == TruffloButtonStyle {
    static var truffloPrimary: TruffloButtonStyle { TruffloButtonStyle(variant: .primary) }
    static var truffloSecondary: TruffloButtonStyle { TruffloButtonStyle(variant: .secondary) }
    static var truffloOutline: TruffloButtonStyle { TruffloButtonStyle(variant: .outline) }
    static var truffloGhost: TruffloButtonStyle { TruffloButtonStyle(variant: .ghost) }
}
