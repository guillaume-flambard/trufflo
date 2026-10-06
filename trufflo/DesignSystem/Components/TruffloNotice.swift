import SwiftUI

/// A full-screen statement for a state that is not an error to acknowledge:
/// an object deleted elsewhere, a journal that could not be opened. A sentence,
/// at most one way out, nothing alarming.
public struct TruffloNotice: View {
    private let systemImage: String?
    private let title: String
    private let message: String
    private let footnote: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(systemImage: String? = nil, title: String, message: String,
                footnote: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.footnote = footnote
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Color.truffloForest)
                    .frame(width: 76, height: 76)
                    .background(Color.truffloMint.opacity(0.45),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.bottom, TruffloTheme.Spacing.xSmall)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.truffloForest)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.truffloSlate)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote {
                Text(footnote)
                    .font(.subheadline)
                    .foregroundStyle(Color.truffloSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.headline)
                    .foregroundStyle(Color.truffloForest)
                    .padding(.horizontal, TruffloTheme.Spacing.large)
                    .frame(minHeight: 50)
                    .background(Color.truffloForest.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, TruffloTheme.Spacing.xSmall)
            }
        }
        .padding(.horizontal, TruffloTheme.Spacing.large + 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.truffloSand.ignoresSafeArea())
    }
}
