import SwiftUI

/// The primary action of the walk screen: 56 pt tall, forest, white label, always
/// the last row of the control surface so it stays under the thumb.
///
/// One primary at a time. Pause while recording; Resume while paused or
/// interrupted. Finishing is never a primary.
public struct TruffloPrimaryAction: View {
    private let title: String
    private let systemImage: String
    private let accessibilityLabel: String
    private let identifier: String
    private let action: () -> Void

    public init(_ title: String,
                systemImage: String,
                accessibilityLabel: String,
                identifier: String,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.truffloForest, in: RoundedRectangle(
                cornerRadius: TruffloTheme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }
}

/// A quiet secondary action: white label on a light rim, no fill of its own, so
/// it reads as the smaller of two choices beside a forest primary.
///
/// Used for ending a walk. The intent is terminal rather than destructive, since
/// the walk is saved, so it carries no red: the confirmation sheet that follows
/// is what protects the tap.
public struct TruffloQuietAction: View {
    private let title: String
    private let systemImage: String
    private let accessibilityLabel: String
    private let identifier: String
    private let action: () -> Void

    public init(_ title: String,
                systemImage: String,
                accessibilityLabel: String,
                identifier: String,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, TruffloTheme.Spacing.medium)
            .frame(height: 56)
            .background(.white.opacity(0.10), in: RoundedRectangle(
                cornerRadius: TruffloTheme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous)
                    .strokeBorder(.white.opacity(0.34), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }
}

/// A small circular glass map control, 44 pt: the minimise chevron and the
/// recentre button. Never smaller, so a thumb finds it without looking.
public struct TruffloRoundAction: View {
    private let systemImage: String
    private let label: String
    private let identifier: String
    private let tint: Color
    private let action: () -> Void

    public init(systemImage: String,
                label: String,
                identifier: String,
                tint: Color = .white,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.identifier = identifier
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .truffloGlassCircle(strength: .strong)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
