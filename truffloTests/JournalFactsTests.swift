import Foundation
import Testing
@testable import trufflo

/// What the journal says about a chien and a period, in one place: Today, the dog
/// list and the dog's page all read these figures, so they can never disagree.
@Suite("Journal facts")
struct JournalFactsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-10-05 is a Monday.
    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private let oslo = UUID()
    private let pixel = UUID()

    private func walk(_ day: Int, _ hour: Int, minutes: Int = 30, phase: WalkPhase = .completed,
                      dogs: Set<UUID>) -> JournalFacts.Walk {
        let end = date(day, hour)
        return .init(id: UUID(), startedAt: end.addingTimeInterval(-Double(minutes * 60)),
                     endedAt: phase == .completed ? end : nil,
                     seconds: TimeInterval(minutes * 60), phase: phase, dogIDs: dogs)
    }

    @Test func aChienCountsOnlyTheFinishedBaladesItWasOn() {
        let facts = JournalFacts(walks: [
            walk(5, 9, dogs: [oslo]),
            walk(5, 18, dogs: [oslo, pixel]),
            walk(6, 8, dogs: [pixel]),
            walk(6, 12, phase: .recording, dogs: [oslo]),
        ], now: date(6, 12), calendar: calendar)
        #expect(facts.walkCount(for: oslo) == 2)
        #expect(facts.walkCount(for: pixel) == 2)
        #expect(facts.walkCount(for: UUID()) == 0)
    }

    @Test func aChienTotalTimeAddsItsFinishedBaladesOnly() {
        let facts = JournalFacts(walks: [
            walk(5, 9, minutes: 35, dogs: [oslo]),
            walk(5, 18, minutes: 20, dogs: [oslo, pixel]),
            walk(6, 12, minutes: 50, phase: .paused, dogs: [oslo]),
        ], now: date(6, 12), calendar: calendar)
        #expect(facts.totalSeconds(for: oslo) == 55 * 60)
        #expect(facts.totalSeconds(for: pixel) == 20 * 60)
    }

    @Test func todayCountsTheChienBaladesOfTheCalendarDayOnly() {
        let facts = JournalFacts(walks: [
            walk(5, 23, dogs: [oslo]),
            walk(6, 0, dogs: [oslo]),
            walk(6, 9, dogs: [oslo, pixel]),
            walk(6, 11, phase: .interrupted, dogs: [oslo]),
        ], now: date(6, 12), calendar: calendar)
        #expect(facts.todayCount(for: oslo) == 2)
        #expect(facts.todayCount(for: pixel) == 1)
    }

    /// The week is the calendar week, Monday to Sunday, on every screen. Read on a
    /// Thursday, last Sunday's balade is not "this week", although it is within
    /// seven days: the Journal used to count it, Today did not.
    @Test func theWeekIsTheCalendarWeekNotTheLastSevenDays() {
        let facts = JournalFacts(walks: [
            walk(4, 10, dogs: [oslo]),
            walk(5, 9, dogs: [oslo]),
            walk(7, 18, dogs: [pixel]),
        ], now: date(8, 12), calendar: calendar)
        #expect(facts.week.walkCount == 2)
        #expect(facts.week.days.map(\.walkCount) == [1, 0, 1, 0, 0, 0, 0])
    }

    @Test func theLastBaladeIsTheLatestFinishedOneAndTheLiveOneIsApart() {
        let older = walk(5, 9, dogs: [oslo])
        let latest = walk(6, 8, dogs: [pixel])
        let live = walk(6, 11, phase: .paused, dogs: [oslo])
        let facts = JournalFacts(walks: [latest, live, older,
                                         walk(6, 10, phase: .discarded, dogs: [oslo])],
                                 now: date(6, 12), calendar: calendar)
        #expect(facts.lastWalkID == latest.id)
        #expect(facts.liveWalkID == live.id)
    }

    @Test func anEmptyJournalHasNoLastBaladeAndNoLiveOne() {
        let facts = JournalFacts(walks: [], now: date(6, 12), calendar: calendar)
        #expect(facts.lastWalkID == nil)
        #expect(facts.liveWalkID == nil)
        #expect(facts.week.isEmpty)
    }

    /// "Dernière balade" is the one that ended last. A balade ajoutée after the
    /// fact can start late and still have ended before another one.
    @Test func theLastBaladeIsTheOneThatEndedLastNotTheOneThatStartedLast() {
        let longMorning = walk(6, 11, minutes: 180, dogs: [oslo])
        let shortLate = walk(6, 10, minutes: 20, dogs: [oslo])
        let facts = JournalFacts(walks: [shortLate, longMorning], now: date(6, 12), calendar: calendar)
        #expect(facts.lastWalkID == longMorning.id)
    }

    /// Two balades en cours can survive a crash; the one started last is the one
    /// the person is on.
    @Test func amongSeveralBaladesEnCoursTheLastStartedIsLive() {
        let first = walk(6, 9, phase: .interrupted, dogs: [oslo])
        let second = walk(6, 11, phase: .recording, dogs: [oslo])
        let facts = JournalFacts(walks: [first, second], now: date(6, 12), calendar: calendar)
        #expect(facts.liveWalkID == second.id)
    }

    /// A finished balade with no end recorded is placed at its start, never lost.
    @Test func aFinishedBaladeWithoutAnEndCountsAtItsStart() {
        let start = date(6, 9)
        let noEnd = JournalFacts.Walk(id: UUID(), startedAt: start, endedAt: nil, seconds: 1200,
                                      phase: .completed, dogIDs: [oslo])
        let facts = JournalFacts(walks: [noEnd], now: date(6, 12), calendar: calendar)
        #expect(facts.todayCount(for: oslo) == 1)
        #expect(facts.week.walkCount == 1)
        #expect(facts.lastWalkID == noEnd.id)
    }
}
