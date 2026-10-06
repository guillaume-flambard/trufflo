import SwiftUI

/// The journal as an activity feed: one card per walk, newest first, grouped
/// under a light day heading. A descriptive count opens the page; nothing is
/// summed, no target is shown.
struct JournalTimelineView: View {
    let walks: [WalkRecord]
    /// Shown instead of the week sentence when the list is filtered.
    var filterSummary: String? = nil
    let rowDestination: (UUID) -> WalkRoute

    @Environment(\.calendar) private var calendar
    private static let locale = Locale(identifier: "fr_FR")

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
                if let sentence = filterSummary ?? weekSentence {
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                }
                ForEach(days, id: \.start) { day in
                    Text(heading(for: day.start))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.truffloForest)
                        .padding(.top, TruffloTheme.Spacing.xSmall)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(day.walks) { walk in
                        NavigationLink(value: rowDestination(walk.id)) {
                            WalkActivityCard(walk: walk, showsDay: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.medium)
            .padding(.vertical, TruffloTheme.Spacing.small)
        }
    }

    private struct Day {
        let start: Date
        let walks: [WalkRecord]
    }

    private var days: [Day] {
        let grouped = Dictionary(grouping: walks) { calendar.startOfDay(for: $0.endedAt ?? $0.startedAt) }
        return grouped.keys.sorted(by: >).map { start in
            Day(start: start, walks: grouped[start]!.sorted {
                ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt)
            })
        }
    }

    private func heading(for day: Date) -> String {
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }
        let text = day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.locale))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The last seven days, not the calendar week, so Monday is not a reset.
    private var weekSentence: String? {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let count = walks.filter { ($0.endedAt ?? $0.startedAt) >= weekAgo }.count
        switch count {
        case 0: return nil
        case 1: return "1 balade enregistrée cette semaine"
        default: return "\(count) balades enregistrées cette semaine"
        }
    }
}
