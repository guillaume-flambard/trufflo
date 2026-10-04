import SwiftUI

public struct TruffloBadge: View {
    public enum Style {
        case forest
        case sage
        case peach
        case sky
        case sand
    }

    private let title: String
    private let icon: String?
    private let style: Style

    public init(_ title: String, icon: String? = nil, style: Style = .sage) {
        self.title = title
        self.icon = icon
        self.style = style
    }

    public var body: some View {
        HStack(spacing: TruffloTheme.Spacing.xxSmall) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title)
                .font(.truffloCaption)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, TruffloTheme.Spacing.small)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch style {
        case .forest: return Color.truffloForest
        case .sage: return Color.truffloSage.opacity(0.2)
        case .peach: return Color.truffloPeach.opacity(0.3)
        case .sky: return Color.truffloSky.opacity(0.3)
        case .sand: return Color.truffloSand
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .forest: return .white
        case .sage: return Color.truffloForest
        case .peach: return Color.truffloTerracotta
        case .sky: return Color.truffloForest
        case .sand: return Color.truffloCharcoal
        }
    }
}
