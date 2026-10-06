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
            .frame(minHeight: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: TruffloTheme.Radius.medium))
        .tint(Color.truffloForest)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }
}

/// A quiet secondary action: a plain glass button beside the forest primary, so
/// it reads as the smaller of the two choices.
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
            .foregroundStyle(.white)
            .padding(.horizontal, TruffloTheme.Spacing.small)
            // 70, not 56: the glass-prominent primary beside it adds its own
            // padding around a 56 pt label, and the two must share a height.
            .frame(minHeight: 70)
            .truffloGlassControl(strength: .strong, interactive: true)
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
                .truffloGlassCircle(strength: .strong, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
