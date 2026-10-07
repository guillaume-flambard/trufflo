import SwiftUI

/// The week of Today as one object: the number of walks, said as a sentence,
/// and the seven days underneath it as its own axis (A2-REQ-03).
///
/// A walked day is a filled disc, a day without one is an empty ring, today is
/// ringed, a day to come is dashed. There is no state for "missed" because the
/// model has none: a person who did not walk on Tuesday has not failed at
/// anything, so nothing here can say so. Shape carries the meaning, colour only
/// backs it up.
///
/// It is content, so it sits on the page with no glass and no card: glass is the
/// navigation and controls layer (Apple, *Adopting Liquid Glass*).
struct TruffloWeekFigure: View {
    let week: WeekSummary
    /// The second line, "2 h 05 en tout", already formatted by the caller.
    let totalLine: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Follows Dynamic Type, capped: at the largest accessibility sizes a uniform
    /// scale would push the figure past the width of the screen.
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 56
    /// What the figure shows. Nil until the screen appears, so the first appearance rolls.
    @State private var shownCount: Int?

    private var calendar: Calendar { TruffloLocale.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                if week.isEmpty {
                    Text("Pas encore de balade cette semaine.")
                        .font(.truffloTitleHeavy)
                        .foregroundStyle(Color.truffloForest)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // The figure beside its caption, not above it: at 112 pt on a line
                    // of its own it pushed the last walk under the start button and the
                    // tab bar (2026-10-07 review). Stacked again at accessibility sizes,
                    // where the side by side leaves the caption a few letters of width.
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: TruffloTheme.Spacing.small))
                    layout {
                        figure
                        VStack(alignment: .leading, spacing: 2) {
                            Text(week.walkCount == 1 ? "balade cette semaine" : "balades cette semaine")
                                .font(.truffloBodyHeavy)
                                .foregroundStyle(Color.truffloCharcoal)
                            if let totalLine {
                                Text(totalLine)
                                    .font(.truffloBodyRegular)
                                    .foregroundStyle(Color.truffloSlate)
                            }
                        }
                    }
                }
            }
            days
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(week.spoken(calendar: calendar))
        .accessibilityIdentifier("today.week")
    }

    private var figure: some View {
        let size = min(figureSize, 96)
        let value = shownCount ?? 0
        return Text(value, format: .number)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(-0.03 * size)
            .monospacedDigit()
            .foregroundStyle(Color.truffloForest)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            // The one authored moment of motion: the figure rolls up to the week's
            // count when the screen first appears, then only when the count changes.
            .contentTransition(.numericText(value: Double(value)))
            .onAppear { roll(to: week.walkCount) }
            .onChange(of: week.walkCount) { _, new in roll(to: new) }
            .accessibilityHidden(true)
    }

    private func roll(to count: Int) {
        if reduceMotion {
            shownCount = count
        } else {
            withAnimation(.smooth(duration: 0.8)) { shownCount = count }
        }
    }

    private var days: some View { TruffloWeekDays(week: week) }
}

/// The seven days of a week as discs with their initial. Shared by the week figure
/// and by the welcome screen, which shows the week as it will look once there is
/// a first walk.
struct TruffloWeekDays: View {
    let week: WeekSummary
    /// The discs appear one after the other, once, instead of all at once.
    var animatesEntrance = false

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var calendar: Calendar { TruffloLocale.calendar }
    private var entrance: Bool { animatesEntrance && !reduceMotion }

    var body: some View {
        let letters = calendar.veryShortStandaloneWeekdaySymbols
        Group {
            if typeSize.isAccessibilitySize {
                // Four and three: each disc keeps its size and its letter instead of
                // shrinking until neither can be read.
                let columns = Array(repeating: GridItem(.flexible(), spacing: TruffloTheme.Spacing.small), count: 4)
                LazyVGrid(columns: columns, alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
                    ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                        dayView(day, index: index, letters: letters)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                        dayView(day, index: index, letters: letters).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onAppear { appeared = true }
    }

    private func dayView(_ day: WeekSummary.Day, index: Int, letters: [String]) -> some View {
        let letter = letters[calendar.component(.weekday, from: day.date) - 1]
        let shown = appeared || !entrance
        return VStack(spacing: TruffloTheme.Spacing.xSmall) {
            WeekDisc(day: day)
                .frame(width: 30, height: 30)
                .padding(5)
                .animation(reduceMotion ? nil : .snappy, value: day.hasWalk)
            Text(letter)
                .font(.truffloMeta).fontWeight(day.isToday ? .heavy : .regular)
                .foregroundStyle(day.isToday ? Color.truffloForest : Color.truffloSlate)
        }
        .scaleEffect(shown ? 1 : 0.5)
        .opacity(shown ? 1 : 0)
        .animation(entrance ? .spring(response: 0.5, dampingFraction: 0.72).delay(0.12 + Double(index) * 0.06) : nil,
                   value: appeared)
    }
}

/// One day. Filled, empty, dashed (to come), and ringed when it is today.
private struct WeekDisc: View {
    let day: WeekSummary.Day

    /// Terracotta darkened to hold 3:1 against the sand page (WCAG 1.4.11).
    private var todayRing: Color { Color.truffloTerracotta.mix(with: .black, by: 0.14) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if day.hasWalk {
                Circle().fill(Color.truffloForest)
            } else if day.isFuture {
                Circle().strokeBorder(Color.truffloSlate.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 2, dash: [2, 4]))
            } else {
                Circle().strokeBorder(Color.truffloSlate.opacity(0.55), lineWidth: 2)
            }
            if day.isToday {
                Circle().strokeBorder(todayRing, lineWidth: 2.5).padding(-6)
            }
        }
        // The moment a walk ends and its day fills: the disc swells and settles, once,
        // and the phone answers with a short success tap. Only when the day flips from
        // empty to walked, never on first appearance, never in a loop.
        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 1.3, 1.0], trigger: day.hasWalk) { content, scale in
            content.scaleEffect(scale)
        } animation: { scale in
            scale > 1 ? .spring(response: 0.25, dampingFraction: 0.5) : .spring(response: 0.4, dampingFraction: 0.7)
        }
        .sensoryFeedback(.success, trigger: day.hasWalk) { old, new in !old && new }
    }
}

#Preview("Semaine, quatre balades") {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "fr_FR")
    let now = Date()
    let week = WeekSummary.make(
        walks: [-1, -2, -4, -4].map { .init(endedAt: now.addingTimeInterval(Double($0) * 86400), seconds: 1500) },
        now: now, calendar: calendar)
    return TruffloWeekFigure(week: week, totalLine: "2 h 05 en tout")
        .padding()
        .background(Color.truffloSand)
}
