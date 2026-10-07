import SwiftUI

/// The mood of a balade as chips, one at most, tapping the chosen one again to
/// clear it (2026-10-07 mock-up). The person's word for the outing, never a score.
struct MoodChips: View {
    @Binding var selection: WalkMood?

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(WalkMood.allCases, id: \.self) { mood in
                let isOn = selection == mood
                Button {
                    withAnimation(.snappy) { selection = isOn ? nil : mood }
                } label: {
                    Label {
                        Text(mood.label)
                    } icon: {
                        Image(systemName: mood.systemImage)
                            .symbolEffect(.bounce, value: isOn)
                    }
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.truffloForest : Color.truffloCharcoal)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(isOn ? Color(red: 0.86, green: 0.93, blue: 0.89) : Color.black.opacity(0.03),
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? Color.truffloForest.opacity(0.35) : .clear, lineWidth: 1))
                }
                .buttonStyle(TruffloPressStyle())
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("walk.mood")
    }
}
