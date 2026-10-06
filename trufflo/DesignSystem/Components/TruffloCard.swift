import SwiftUI

public struct TruffloCard<Content: View>: View {
    public enum Variant {
        case sand
        case mint
        case plain
    }

    private let variant: Variant
    private let content: Content

    public init(variant: Variant = .sand, @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.content = content()
    }

    public var body: some View {
        content
            .padding(TruffloTheme.Spacing.medium)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
                    .stroke(Color.truffloForest.opacity(0.06), lineWidth: 1)
            )
    }

    private var backgroundColor: Color {
        switch variant {
        case .sand:
            return Color.truffloSand
        case .mint:
            return Color.truffloMint.opacity(0.35)
        case .plain:
            return Color.white
        }
    }
}
