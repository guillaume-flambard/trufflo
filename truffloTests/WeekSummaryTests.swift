import Foundation
import Testing
@testable import trufflo

/// Today's week is the calendar week, Monday to Sunday: the figure, the sentence
/// and the seven days must all say the same thing (A2-REQ-01, A2-REQ-02).
@Suite("Week summary")
struct WeekSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-10-05 is a Monday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func walk(_ day: Int, _ hour: Int, minutes: Int = 30, minute: Int = 0, month: Int = 10) -> WeekSummary.Walk {
        .init(endedAt: date(day, hour, minute, month: month), seconds: TimeInterval(minutes * 60))
    }

    @Test func aTuesdayCountsMondayAndTuesdayAndNotTheSundayBefore() {
        let walks = [walk(5, 9), walk(5, 18), walk(6, 8), walk(4, 22)]
        let week = WeekSummary.make(walks: walks, now: date(6, 12), calendar: calendar)
        #expect(week.walkCount == 3)
        #expect(week.days.map(\.walkCount) == [2, 1, 0, 0, 0, 0, 0])
        #expect(week.days.map(\.hasWalk) == [true, true, false, false, false, false, false])
    }

    @Test func theWeekStartsOnMondayAndHasSevenDays() {
        let week = WeekSummary.make(walks: [], now: date(8, 12), calendar: calendar)
        #expect(week.days.count == 7)
        #expect(calendar.component(.weekday, from: week.days[0].date) == 2, "le premier jour est un lundi")
        #expect(calendar.component(.weekday, from: week.days[6].date) == 1, "le dernier est un dimanche")
    }

    @Test func aSundayLateEveningWalkStillBelongsToThatWeek() {
        let week = WeekSummary.make(walks: [walk(11, 23, minute: 10)], now: date(11, 23, 30), calendar: calendar)
        #expect(week.walkCount == 1)
        #expect(week.days[6].hasWalk)
        #expect(week.days[6].isToday)
    }

    @Test func theBoundariesAreExactAtMidnight() {
        let mondayMidnight = WeekSummary.Walk(endedAt: date(5, 0, 0), seconds: 600)
        let sundayJustBefore = WeekSummary.Walk(endedAt: date(5, 0, 0).addingTimeInterval(-1), seconds: 600)
        let week = WeekSummary.make(walks: [mondayMidnight, sundayJustBefore], now: date(7, 9), calendar: calendar)
        #expect(week.walkCount == 1, "minuit pile du lundi entre, la seconde d'avant sort")
    }

    @Test func todayIsMarkedWhetherOrNotItHasAWalk() {
        let without = WeekSummary.make(walks: [walk(5, 9)], now: date(7, 12), calendar: calendar)
        #expect(without.days.filter(\.isToday).map(\.hasWalk) == [false])
        let with = WeekSummary.make(walks: [walk(7, 8)], now: date(7, 12), calendar: calendar)
        #expect(with.days.filter(\.isToday).map(\.hasWalk) == [true])
    }

    @Test func daysAfterTodayAreFutureAndOthersAreNot() {
        let week = WeekSummary.make(walks: [], now: date(7, 12), calendar: calendar)
        #expect(week.days.map(\.isFuture) == [false, false, false, true, true, true, true])
    }

    @Test func anEmptyWeekHasNoWalkAndNoTime() {
        let week = WeekSummary.make(walks: [walk(1, 9, month: 9)], now: date(7, 12), calendar: calendar)
        #expect(week.walkCount == 0)
        #expect(week.totalSeconds == 0)
        #expect(week.isEmpty)
    }

    @Test func theTotalTimeIsTheSumOfTheWeeksWalksOnly() {
        let walks = [walk(5, 9, minutes: 35), walk(6, 9, minutes: 20), walk(3, 9, minutes: 90)]
        let week = WeekSummary.make(walks: walks, now: date(7, 12), calendar: calendar)
        #expect(week.totalSeconds == 55 * 60)
    }

    @Test func theSpokenSentenceNamesWalksAndDaysWithoutAnyJudgement() {
        let walks = [walk(5, 9), walk(7, 8), walk(7, 18)]
        let week = WeekSummary.make(walks: walks, now: date(7, 20), calendar: calendar)
        let sentence = week.spoken(calendar: calendar)
        #expect(sentence.contains("3 balades cette semaine"))
        #expect(sentence.contains("lundi"))
        #expect(sentence.contains("mercredi"))
        for forbidden in ["manqu", "raté", "objectif", "série", "retard"] {
            #expect(!sentence.lowercased().contains(forbidden))
        }
    }

    @Test func theSpokenSentenceOfAnEmptyWeekHasNoZero() {
        let week = WeekSummary.make(walks: [], now: date(7, 12), calendar: calendar)
        let sentence = week.spoken(calendar: calendar)
        #expect(!sentence.contains("0"))
        #expect(sentence.contains("Pas encore de balade cette semaine"))
    }

    @Test func oneWalkIsSingular() {
        let week = WeekSummary.make(walks: [walk(6, 9)], now: date(7, 12), calendar: calendar)
        #expect(week.spoken(calendar: calendar).contains("1 balade cette semaine"))
    }
}
