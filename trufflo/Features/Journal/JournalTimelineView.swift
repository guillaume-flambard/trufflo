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
    /// The photo head of the screen, and the chips under it (2026-10-07 mock-up).
    var hero: AnyView? = nil
    var chips: AnyView? = nil
    @State private var topInset: CGFloat = 0

    @Environment(\.calendar) private var calendar
    private static let locale = TruffloLocale.french

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The photo runs up under the status bar: pulled up by the top inset
                // instead of letting the scroll view ignore the safe area, which made
                // the tab bar believe the list had scrolled and fold away.
                if let hero { hero.environment(\.heroTopInset, topInset).padding(.top, -topInset) }
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let chips { chips }
                    LostHouseholdNotice()
                    // The mock-up's journal opens on its chips, with no count sentence.
                    if let sentence = filterSummary ?? (chips == nil ? weekSentence : nil) {
                        Text(sentence)
                            .font(.subheadline)
                            .foregroundStyle(Color.truffloSlate)
                    }
                    ForEach(days, id: \.start) { day in
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                            TruffloSectionTitle(heading(for: day.start))
                            ForEach(day.items) { item in
                                switch item {
                                case .own(let walk):
                                    NavigationLink(value: rowDestination(walk.id)) {
                                        JournalWalkTile(walk: walk)
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
                .padding(.top, hero == nil ? 8 : 14)
                .padding(.bottom, TruffloTheme.Spacing.large)
                .background {
                    // Under a photo head the list rises on a sand sheet; under the
                    // plain head it sits on the screen's own aura.
                    if hero != nil {
                        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                            .fill(Color.truffloSand)
                    }
                }
                .padding(.top, hero == nil ? 0 : -40)
            }
        }
        .scrollEdgeEffectHidden(hero != nil, for: .top)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
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
        let text = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Self.locale))
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
