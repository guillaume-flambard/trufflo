import Foundation

/// The calendar week of Today: Monday to Sunday, one entry per day.
///
/// Descriptive only. A day is walked or it is not; nothing here knows a target,
/// a streak or a missed day, so no screen built on it can show one.
public struct WeekSummary: Equatable, Sendable {
    /// One finished walk of the person, reduced to what the week needs.
    public struct Walk: Equatable, Sendable {
        public let endedAt: Date
        public let seconds: TimeInterval

        public init(endedAt: Date, seconds: TimeInterval) {
            self.endedAt = endedAt
            self.seconds = seconds
        }
    }

    public struct Day: Equatable, Sendable, Identifiable {
        public let date: Date
        public let walkCount: Int
        public let isToday: Bool
        public let isFuture: Bool

        public var id: Date { date }
        public var hasWalk: Bool { walkCount > 0 }
    }

    public let days: [Day]
    public let walkCount: Int
    public let totalSeconds: TimeInterval

    public var isEmpty: Bool { walkCount == 0 }

    /// Walks outside the week of `now` are ignored. Both boundaries belong to
    /// the week they open: Monday 00:00:00 is in, the second before it is not.
    public static func make(walks: [Walk], now: Date, calendar: Calendar) -> WeekSummary {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return WeekSummary(days: [], walkCount: 0, totalSeconds: 0)
        }
        let inWeek = walks.filter { week.contains($0.endedAt) }
        let days = (0..<7).compactMap { offset -> Day? in
            guard let start = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let count = inWeek.filter { calendar.isDate($0.endedAt, inSameDayAs: start) }.count
            return Day(date: start,
                       walkCount: count,
                       isToday: calendar.isDate(start, inSameDayAs: now),
                       isFuture: calendar.startOfDay(for: start) > calendar.startOfDay(for: now))
        }
        return WeekSummary(days: days,
                           walkCount: inWeek.count,
                           totalSeconds: inWeek.map(\.seconds).reduce(0, +))
    }

    /// The week as one sentence for VoiceOver: the count, the days walked, and
    /// today when it has no walk yet. No judgement word, no zero.
    public func spoken(calendar: Calendar) -> String {
        func name(_ day: Day) -> String {
            let index = calendar.component(.weekday, from: day.date) - 1
            return calendar.standaloneWeekdaySymbols[index]
        }
        guard !isEmpty else { return "Pas encore de balade cette semaine." }
        let noun = walkCount == 1 ? "balade" : "balades"
        let walked = days.filter(\.hasWalk).map(name).formatted(.list(type: .and).locale(TruffloLocale.french))
        var sentence = "\(walkCount) \(noun) cette semaine. Jours de balade : \(walked)."
        if let today = days.first(where: \.isToday), !today.hasWalk {
            sentence += " Aujourd'hui, \(name(today)), pas encore de balade."
        }
        return sentence
    }
}
