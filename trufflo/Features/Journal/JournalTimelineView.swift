import SwiftUI

/// The journal as a feed: one card per balade (the same card as Today), newest
/// first, under a day heading. A descriptive count opens the page; nothing is
/// summed, no target is shown.
struct JournalTimelineView: View {
    let walks: [WalkRecord]
    /// Walks of the other household members, read-only (PRD F08).
    var shared: [SharedEntry] = []
    /// Shown instead of the week sentence when the list is filtered.
    var filterSummary: String? = nil
    /// My balades of the calendar week, the number Today shows (`JournalFacts.week`).
    let weekCount: Int
    /// The namespace of the zoom from a row to its walk.
    let zoom: Namespace.ID
    let rowDestination: (UUID) -> WalkRoute

    @Environment(\.calendar) private var calendar
    private static let locale = TruffloLocale.french

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                LostHouseholdNotice()
                if let sentence = filterSummary ?? weekSentence {
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                }
                ForEach(days, id: \.start) { day in
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        Text(heading(for: day.start))
                            .font(.truffloBodyHeavy)
                            .foregroundStyle(Color.truffloForest)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(day.items) { item in
                            switch item {
                            case .own(let walk):
                                NavigationLink(value: rowDestination(walk.id)) {
                                    WalkTile(walk: walk)
                                }
                                .buttonStyle(.plain)
                                .matchedTransitionSource(id: walk.id, in: zoom)
                            case .shared(let entry):
                                NavigationLink(value: SharedWalkRoute(id: entry.walk.id)) {
                                    SharedWalkCard(walk: entry.walk, authorName: entry.authorName,
                                                   possibleDuplicate: entry.possibleDuplicate)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.vertical, TruffloTheme.Spacing.small)
        }
    }

    struct SharedEntry {
        let walk: SharedWalkRecord
        let authorName: String
        let possibleDuplicate: Bool
    }

    private enum Item: Identifiable {
        case own(WalkRecord)
        case shared(SharedEntry)

        var id: UUID {
            switch self {
            case .own(let walk): walk.id
            case .shared(let entry): entry.walk.id
            }
        }

        var date: Date {
            switch self {
            case .own(let walk): walk.endedAt ?? walk.startedAt
            case .shared(let entry): entry.walk.endedAt
            }
        }
    }

    private struct Day {
        let start: Date
        let items: [Item]
    }

    private var days: [Day] {
        let items = walks.map(Item.own) + shared.map(Item.shared)
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { start in
            Day(start: start, items: grouped[start]!.sorted { $0.date > $1.date })
        }
    }

    private func heading(for day: Date) -> String {
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }
        let text = day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.locale))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The calendar week, as on Today: "cette semaine" has one meaning.
    private var weekSentence: String? {
        switch weekCount {
        case 0: return nil
        case 1: return "1 balade enregistrée cette semaine"
        default: return "\(weekCount) balades enregistrées cette semaine"
        }
    }
}
