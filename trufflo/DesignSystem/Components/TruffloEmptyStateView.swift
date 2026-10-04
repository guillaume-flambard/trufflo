import SwiftUI

public struct TruffloEmptyStateView: View {
    private let imageName: String
    private let title: String
    private let description: String
    private let buttonTitle: String?
    private let action: (() -> Void)?

    public init(
        imageName: String,
        title: String,
        description: String,
        buttonTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.imageName = imageName
        self.title = title
        self.description = description
        self.buttonTitle = buttonTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: TruffloTheme.Spacing.large) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))

            VStack(spacing: TruffloTheme.Spacing.small) {
                Text(title)
                    .font(.truffloHeadline)
                    .foregroundStyle(Color.truffloForest)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.truffloBody)
                    .foregroundStyle(Color.truffloCharcoal.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TruffloTheme.Spacing.medium)

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.truffloPrimary)
                    .padding(.horizontal, TruffloTheme.Spacing.large)
            }
        }
        .padding(TruffloTheme.Spacing.large)
    }
}
