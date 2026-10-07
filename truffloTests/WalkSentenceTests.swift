import Foundation
import Testing
@testable import trufflo

/// The line under a finished walk says what it was: when, and which of the week.
/// Descriptive only. No target, no comparison with another walk or another dog.
@Suite("Walk sentence")
struct WalkSentenceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: hour, minute: 30))!
    }

    @Test(arguments: [(6, "du matin"), (11, "du matin"), (13, "de l'après-midi"), (17, "de l'après-midi"),
                      (19, "du soir"), (22, "du soir"), (2, "de nuit")])
    func theMomentOfTheDayIsNamed(_ hour: Int, _ expected: String) {
        let sentence = WalkSentence.make(endedAt: at(hour), weekCount: 2, calendar: calendar)
        #expect(sentence.contains(expected), "à \(hour) h : \(sentence)")
    }

    @Test func theFirstWalkOfTheWeekSaysSo() {
        let sentence = WalkSentence.make(endedAt: at(9), weekCount: 1, calendar: calendar)
        #expect(sentence == "Balade du matin, la première de la semaine.")
    }

    @Test func laterWalksCarryTheirOrdinalInFrench() {
        #expect(WalkSentence.make(endedAt: at(9), weekCount: 2, calendar: calendar)
                == "Balade du matin, la 2e de la semaine.")
        #expect(WalkSentence.make(endedAt: at(19), weekCount: 7, calendar: calendar)
                == "Balade du soir, la 7e de la semaine.")
    }

    @Test func noJudgementWordEverAppears() {
        for count in 1...12 {
            let sentence = WalkSentence.make(endedAt: at(9), weekCount: count, calendar: calendar).lowercased()
            for forbidden in ["record", "objectif", "mieux", "moins", "plus que", "bravo", "série", "retard", "manqu"] {
                #expect(!sentence.contains(forbidden), "\(sentence)")
            }
        }
    }

    @Test func aWeekCountOfZeroFallsBackToTheMomentAlone() {
        // Should not happen (the walk itself is in its week); never print "la 0e".
        #expect(WalkSentence.make(endedAt: at(9), weekCount: 0, calendar: calendar) == "Balade du matin.")
    }
}
