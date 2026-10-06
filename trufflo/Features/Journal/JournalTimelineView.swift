import SwiftUI

/// The journal as a chronicle: a day heading, then the outings of that day along a
/// single vertical rule. No cards and no badges, because the information is in the
/// wording and the marker.
///
/// A recorded outing has a filled dot, a declared one an open ring, so the origin
/// is not carried by colour or by a pill. VoiceOver gets the origin spelled out,
/// since the marker is silent.
///
/// A row shows a distance only when this very outing measured one. Nothing sums
/// distances and nothing writes "Non mesurée" on every line: a missing measurement
/// is stated once, in the detail.
struct JournalTimelineView: View {
    let walks: [WalkRecord]
    let dogNames: (UUID) -> String
    let rowDestination: (UUID) -> WalkRoute

    @Environment(\.calendar) private var calendar

    private static let locale = Locale(identifier: "fr_FR")

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                if let sentence = weekSentence {
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                }
                ForEach(days, id: \.start) { day in
                    // Spacing 0: the rule must run unbroken from one dot to the next,
                    // so the gap between outings lives inside each row.
                    VStack(alignment: .leading, spacing: 0) {
                        Text(heading(for: day.start))
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.truffloForest)
                            .padding(.bottom, TruffloTheme.Spacing.xSmall)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(day.walks.enumerated()), id: \.element.id) { index, walk in
                            row(walk, isLast: index == day.walks.count - 1)
                        }
                    }
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.large)
            .padding(.vertical, TruffloTheme.Spacing.medium)
        }
    }

    // MARK: - Rows

    private func row(_ walk: WalkRecord, isLast: Bool) -> some View {
        let isGPS = walk.source != .manual
        let names = dogNames(walk.id)
        return NavigationLink(value: rowDestination(walk.id)) {
            HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
                marker(filled: isGPS, isLast: isLast)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(timeText(walk))
                            .font(.subheadline)
                            .foregroundStyle(Color.truffloSlate)
                            .monospacedDigit()
                        Text(names.isEmpty ? "Balade" : names)
                            .font(.headline)
                            .foregroundStyle(Color.truffloForest)
                        Spacer(minLength: TruffloTheme.Spacing.xSmall)
                        Text(figures(walk, isGPS: isGPS))
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.truffloForest)
                    }
                    if !walk.note.isEmpty {
                        Text(walk.note)
                            .font(.subheadline)
                            .foregroundStyle(Color.truffloCharcoal)
                            .lineLimit(2)
                    }
                }
                .padding(.bottom, isLast ? 0 : TruffloTheme.Spacing.small)
            }
            // Gives the marker column the height of the row, so the rule runs
            // down to the next dot instead of stopping a few points under this one.
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(walk, names: names, isGPS: isGPS))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("walk.row.\(walk.id.uuidString)")
    }

    /// Dot or ring, joined to the next row by a rule that stops at the last
    /// outing of the day.
    private func marker(filled: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if filled {
                    Circle().fill(Color.truffloForest)
                } else {
                    Circle().strokeBorder(Color.truffloForest, lineWidth: 2)
                }
            }
            .frame(width: 12, height: 12)
            .padding(.top, 5)
            if !isLast {
                Rectangle()
                    .fill(Color.truffloForest.opacity(0.18))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }

    // MARK: - Text

    private func timeText(_ walk: WalkRecord) -> String {
        (walk.endedAt ?? walk.startedAt)
            .formatted(.dateTime.hour().minute().locale(Self.locale))
    }

    /// Duration, then the distance when this outing measured one.
    private func figures(_ walk: WalkRecord, isGPS: Bool) -> String {
        let minutes = (walk.confirmedSeconds / 60).formatted(
            .number.precision(.fractionLength(0)).locale(Self.locale))
        let duration = "\(minutes) min"
        guard isGPS, let meters = walk.recordedPathMeters else { return duration }
        return "\(duration), \(WalkFormatting.distance(meters))"
    }

    private func spokenLabel(_ walk: WalkRecord, names: String, isGPS: Bool) -> String {
        var parts = [isGPS ? "Suivi GPS" : "Saisie manuelle"]
        parts.append(names.isEmpty ? "Balade" : "Balade avec \(names)")
        parts.append((walk.endedAt ?? walk.startedAt).formatted(
            .dateTime.weekday(.wide).day().month().hour().minute().locale(Self.locale)))
        parts.append(figures(walk, isGPS: isGPS))
        if !walk.note.isEmpty { parts.append(walk.note) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Grouping

    private struct Day {
        let start: Date
        let walks: [WalkRecord]
    }

    /// Completed outings, newest day first, newest outing first within a day.
    private var days: [Day] {
        let grouped = Dictionary(grouping: walks) {
            calendar.startOfDay(for: $0.endedAt ?? $0.startedAt)
        }
        return grouped.keys.sorted(by: >).map { start in
            Day(start: start,
                walks: grouped[start]!.sorted {
                    ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt)
                })
        }
    }

    private func heading(for day: Date) -> String {
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.locale))
            .capitalizedFirst
    }

    /// Descriptive only: a count over the last seven days. No total, no target,
    /// and nothing when the week is empty.
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

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
