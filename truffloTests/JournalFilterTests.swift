import Foundation
import Testing
@testable import trufflo

private let now = Date(timeIntervalSince1970: 1_791_300_000)
private let oslo = UUID()
private let mirabelle = UUID()

@Test func noFilterShowsEveryWalk() {
    let filter = JournalFilter()
    #expect(!filter.isActive)
    #expect(filter.includes(date: now.addingTimeInterval(-400 * 86_400), dogIDs: [], now: now))
}

@Test func aDogFilterKeepsTheWalksThatDogTookPart() {
    let filter = JournalFilter(dogID: oslo)
    #expect(filter.isActive)
    #expect(filter.includes(date: now, dogIDs: [oslo], now: now))
    // A walk with several dogs belongs to each of them.
    #expect(filter.includes(date: now, dogIDs: [oslo, mirabelle], now: now))
    #expect(!filter.includes(date: now, dogIDs: [mirabelle], now: now))
    // A walk whose dog profile was deleted has no matching dog.
    #expect(!filter.includes(date: now, dogIDs: [], now: now))
}

@Test func periodsCountBackFromNow() {
    let week = JournalFilter(period: .lastSevenDays)
    #expect(week.includes(date: now.addingTimeInterval(-6 * 86_400), dogIDs: [], now: now))
    #expect(!week.includes(date: now.addingTimeInterval(-8 * 86_400), dogIDs: [], now: now))
    let month = JournalFilter(period: .lastThirtyDays)
    #expect(month.includes(date: now.addingTimeInterval(-29 * 86_400), dogIDs: [], now: now))
    #expect(!month.includes(date: now.addingTimeInterval(-31 * 86_400), dogIDs: [], now: now))
}

@Test func thisYearFollowsTheCalendarYear() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let year = JournalFilter(period: .thisYear)
    let startOfYear = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 1))!
    let lastYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 23, minute: 59))!
    #expect(year.includes(date: startOfYear, dogIDs: [], now: now, calendar: calendar))
    #expect(!year.includes(date: lastYear, dogIDs: [], now: now, calendar: calendar))
}

@Test func dogAndPeriodCombine() {
    let filter = JournalFilter(dogID: oslo, period: .lastSevenDays)
    #expect(filter.includes(date: now, dogIDs: [oslo], now: now))
    #expect(!filter.includes(date: now.addingTimeInterval(-10 * 86_400), dogIDs: [oslo], now: now))
    #expect(!filter.includes(date: now, dogIDs: [mirabelle], now: now))
}
