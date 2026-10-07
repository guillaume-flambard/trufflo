import SwiftUI

/// What Today says before there is a dog (A-REQ-06, A2).
///
/// No illustration: a stock picture of a collar belongs to no one's dog, and the
/// rest of the app refuses stand-in faces. What this screen shows instead is the
/// week as it will look, seven empty days, and the empty slot where the dog's
/// portrait will go. Adding the dog fills both, which is the whole promise.
struct TruffloWelcome: View {
    /// Opens the dog form. The slot and the anchored button share it.
    let onAddDog: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var emptyWeek: WeekSummary {
        WeekSummary.make(walks: [], now: .now, calendar: TruffloLocale.calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xLarge) {
            Button(action: onAddDog) {
                Circle()
                    .strokeBorder(Color.truffloSlate.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 2.5, dash: [3, 6]))
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.truffloForest)
                    }
                    .frame(width: typeSize.isAccessibilitySize ? 96 : 128,
                           height: typeSize.isAccessibilitySize ? 96 : 128)
            }
            .buttonStyle(.plain)
            // The anchored button below is the one action for VoiceOver.
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                Text("Qui part en balade ?")
                    .font(.truffloTitleHeavy)
                    .foregroundStyle(Color.truffloForest)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ajoutez votre chien. Chaque balade s'écrira ici, avec son temps, son tracé et vos notes.")
                    .font(.truffloBodyRegular)
                    .foregroundStyle(Color.truffloSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TruffloWeekDays(week: emptyWeek, animatesEntrance: true)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TruffloTheme.Spacing.screen)
        .padding(.top, TruffloTheme.Spacing.xLarge)
    }
}

#Preview("Accueil sans chien") {
    TruffloWelcome(onAddDog: {})
        .background(Color.truffloSand)
}
