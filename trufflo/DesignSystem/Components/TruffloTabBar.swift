import SwiftUI

/// The tab bar of the mock-up: a wide floating glass bar, grey symbols and
/// labels, the current tab on a mint capsule. Drawn by the app because the
/// system bar has neither the capsule nor the colours.
struct TruffloTabBar: View {
    struct Item: Identifiable {
        let tag: Int
        let title: String
        let systemImage: String
        let identifier: String
        var id: Int { tag }
    }

    @Binding var selection: Int
    let items: [Item]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = item.tag == selection
                Button {
                    withAnimation(TruffloTheme.Motion.selection(reduceMotion: reduceMotion)) { selection = item.tag }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 22, weight: .semibold))
                            .frame(height: 26)
                        Text(item.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? Color.truffloForest : Color(red: 0.43, green: 0.43, blue: 0.43))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if isSelected {
                            Capsule().fill(Color(red: 0.84, green: 0.92, blue: 0.86))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier(item.identifier)
            }
        }
        .padding(6)
        .glassEffect(.regular.tint(Color(red: 0.98, green: 0.97, blue: 0.94).opacity(0.75)), in: Capsule())
        .shadow(color: Color(red: 0.35, green: 0.3, blue: 0.2).opacity(0.08), radius: 16, y: 4)
        .padding(.horizontal, TruffloTheme.Spacing.screen)
        // Down into the home-indicator area, as in the mock-up.
        .padding(.bottom, -14)
    }
}
