import SwiftUI

/// "Conseil du jour" (2026-10-07 mock-up): one short, general piece of advice for
/// the walk, a new one each day, dismissible for the day. The advice comes from
/// the server's `daily_tips` table, read without an account and kept offline.
///
/// The advice is about the outing, never about the dog: nothing here reads the
/// journal or says what the dog likes or needs. There is no weather source in
/// the app, so no line claims what the weather is.
struct TruffloDailyTip: View {
    @AppStorage("dailyTipDismissedDay") private var dismissedDay = ""

    /// The tips last read from the server (`DailyTipsRemote`, refreshed by the
    /// root view at launch and on return to the foreground); none until a first
    /// read succeeds, and then no card rather than an invented tip.
    @AppStorage(DailyTipsRemote.cacheKey) private var cache: Data?

    private var today: String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    private var tip: DailyTip? {
        DailyTips.pick(from: DailyTips.decodeCache(cache),
                       dayNumber: Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0)
    }

    var body: some View {
        if dismissedDay != today, let tip {
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
                    Text(tip.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    Text(tip.body)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.truffloForest.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { dismissedDay = today }
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
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}
