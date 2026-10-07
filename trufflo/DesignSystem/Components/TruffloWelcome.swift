import SwiftUI

/// The empty states of the 2026-10-07 board: an illustration, a title, one line,
/// one green button and, when given, a quiet link under it.
struct TruffloEmptyScene: View {
    enum Picture { case walkers, journal }

    let picture: Picture
    let title: String
    let message: String
    let buttonTitle: String
    let buttonIcon: String
    let buttonIdentifier: String
    let action: () -> Void
    var linkTitle: String? = nil
    var linkAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            illustration
                .frame(height: 220)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.truffloForest)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.truffloSlate)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Label(buttonTitle, systemImage: buttonIcon)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.truffloForest)
            .accessibilityIdentifier(buttonIdentifier)
            .padding(.top, 6)
            if let linkTitle, let linkAction {
                Button(linkTitle, action: linkAction)
                    .font(.system(size: 14, weight: .medium))
                    .underline()
                    .foregroundStyle(Color.truffloForest)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var illustration: some View {
        switch picture {
        case .walkers:
            ZStack {
                Circle().fill(Color(red: 0.98, green: 0.78, blue: 0.4)).frame(width: 42).offset(x: -80, y: -70)
                Image(systemName: "cloud.fill").font(.system(size: 40))
                    .foregroundStyle(Color(red: 0.85, green: 0.93, blue: 0.88)).offset(x: 80, y: -80)
                Ellipse().fill(Color(red: 0.84, green: 0.92, blue: 0.86)).frame(width: 240, height: 120).offset(y: 40)
                Image(systemName: "tree.fill").font(.system(size: 70))
                    .foregroundStyle(Color(red: 0.70, green: 0.85, blue: 0.75)).offset(x: -70, y: 0)
                HStack(alignment: .bottom, spacing: -6) {
                    Image(systemName: "figure.walk").font(.system(size: 92, weight: .light))
                    Image(systemName: "dog.fill").font(.system(size: 54))
                }
                .foregroundStyle(Color.truffloForest)
                .offset(y: 20)
            }
        case .journal:
            Image(systemName: "book.pages")
                .font(.system(size: 90, weight: .ultraLight))
                .foregroundStyle(Color.truffloForest.opacity(0.8))
        }
    }
}
