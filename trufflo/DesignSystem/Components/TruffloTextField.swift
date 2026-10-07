import SwiftUI

public struct TruffloTextField: View {
    private let label: String
    private let placeholder: String
    private let icon: String?
    @Binding private var text: String
    private let errorMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        icon: String? = nil,
        errorMessage: String? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.icon = icon
        self.errorMessage = errorMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
            if !label.isEmpty {
                Text(label)
                    .font(.truffloCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.truffloForest)
            }

            HStack(spacing: TruffloTheme.Spacing.small) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(Color.truffloForest.opacity(0.7))
                }

                TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                    .font(.truffloBody)
                    .foregroundStyle(Color.truffloCharcoal)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.truffloCharcoal.opacity(0.4))
                    }
                    .buttonStyle(TruffloClearFieldButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(TruffloTheme.Motion.appear(reduceMotion: reduceMotion), value: text.isEmpty)
            .padding(TruffloTheme.Spacing.medium)
            .background(Color.truffloSand)
            .clipShape(RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous)
                    .stroke(errorMessage != nil ? Color.truffloDanger : Color.truffloForest.opacity(0.1), lineWidth: 1)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.truffloCaption)
                    .foregroundStyle(Color.truffloDanger)
            }
        }
    }
}

/// Press feedback for the clear-field control: it had none at all.
private struct TruffloClearFieldButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(TruffloTheme.Motion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, isPressed in isPressed }
    }
}
