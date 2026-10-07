import SwiftUI

/// "Conseil du jour" (2026-10-07 mock-up): one short, general piece of advice for
/// the walk, a new one each day, dismissible for the day.
///
/// The advice is about the outing, never about the dog: nothing here reads the
/// journal or says what the dog likes or needs. There is no weather source in
/// the app, so no line claims what the weather is.
struct TruffloDailyTip: View {
    @AppStorage("dailyTipDismissedDay") private var dismissedDay = ""

    // Two short lines each, the length the card holds above the tab bar.
    private static let tips = [
        ("Un nouveau coin à explorer ?", "Changer de rue, c'est de nouvelles odeurs."),
        ("Pensez à l'eau.", "Une gourde et un bol pliable suffisent."),
        ("Prenez votre temps.", "Renifler fait aussi partie de la balade."),
        ("Le soir tombe tôt.", "Une veste claire aide à être vus."),
        ("Un sac de plus.", "Glissez-en un de rechange dans la laisse."),
        ("Des pattes propres.", "Un coup d'œil aux coussinets au retour."),
        ("À plusieurs ?", "Le foyer partagé dit qui est déjà sorti."),
    ]

    private var today: String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    private var tip: (String, String) {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return Self.tips[day % Self.tips.count]
    }

    var body: some View {
        if dismissedDay != today {
            HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
                Image(systemName: "leaf")
                    .font(.title3)
                    .foregroundStyle(Color.truffloForest)
                    .frame(width: 44, height: 44)
                    .background(Color(red: 0.80, green: 0.90, blue: 0.83), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conseil du jour")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.truffloForest)
                    Text(tip.0)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    Text(tip.1)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.truffloForest.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    dismissedDay = today
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                        .frame(width: 24, height: 24)
                        // The tap target stays 44 pt while the drawn cross is small.
                        .padding(10)
                        .contentShape(Rectangle())
                        .padding(-10)
                }
                .accessibilityLabel("Masquer le conseil du jour")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(red: 0.89, green: 0.94, blue: 0.90).opacity(0.92),
                        in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
            .accessibilityIdentifier("today.tip")
        }
    }
}
