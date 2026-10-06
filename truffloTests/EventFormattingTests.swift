import Foundation
import Testing
@testable import trufflo

private func event(humans: Int = 4, humansIn: Int = 1, dogs: Int = 3, dogsIn: Int = 1,
                   status: WalkEventStatus = .published, mine: ParticipationStatus? = nil,
                   at: Date = Date(timeIntervalSince1970: 2_000_000)) -> WalkEventDTO {
    WalkEventDTO(id: UUID(), organizerID: UUID(), organizerName: "Léa", zoneID: "z", startsAt: at, durationMinutes: 60,
                 meetingPoint: "Entrée nord", rules: "", humanCapacity: humans, dogCapacity: dogs,
                 humansAccepted: humansIn, dogsAccepted: dogsIn, status: status, myStatus: mine)
}

@Test(arguments: [(45, "45 min"), (60, "1 h"), (90, "1 h 30"), (125, "2 h 05")])
func durationReadsInFrench(_ minutes: Int, _ expected: String) {
    #expect(EventFormatting.duration(minutes) == expected)
}

@Test func placesLeftAreCountedFromWhatIsAccepted() {
    #expect(EventFormatting.places(event()) == "3 places, 2 places pour des chiens")
    #expect(EventFormatting.places(event(humans: 2, humansIn: 1, dogs: 2, dogsIn: 1)) == "1 place, 1 place pour un chien")
    #expect(EventFormatting.places(event(humans: 2, humansIn: 2)) == "Complète")
    #expect(EventFormatting.places(event(dogs: 1, dogsIn: 1)) == "3 places, plus de place pour les chiens")
}

@Test func myOwnRequestIsSaidInWords() {
    // The default event is in 1970: « now » is set before it, so it is still to come.
    let before = Date(timeIntervalSince1970: 1_000_000)
    func said(_ event: WalkEventDTO, organizer: Bool = false) -> String? {
        EventFormatting.myStatus(event, organizerIsMe: organizer, now: before)
    }
    #expect(said(event(mine: .requested)) == "Demande envoyée")
    #expect(said(event(mine: .accepted)) == "Vous venez")
    #expect(said(event(mine: .declined)) == "Demande refusée")
    #expect(said(event(mine: .withdrawn)) == nil)
    #expect(said(event(), organizer: true) == "Vous organisez")
    #expect(said(event(status: .cancelled, mine: .accepted)) == "Annulée")
}

@Test func afterTheWalkTheTenseChangesAndAttendanceIsSaid() {
    let past = Date(timeIntervalSince1970: 1_000_000)
    let later = past.addingTimeInterval(3 * 3600)
    var accepted = event(mine: .accepted, at: past)
    #expect(EventFormatting.myStatus(accepted, now: later) == "Vous y étiez inscrit")
    accepted.myAttended = true
    #expect(EventFormatting.myStatus(accepted, now: later) == "Vous y étiez")
    accepted.myAttended = false
    #expect(EventFormatting.myStatus(accepted, now: later) == "Vous n'y étiez pas")
    #expect(EventFormatting.myStatus(accepted, now: past.addingTimeInterval(-60)) == "Vous venez")
    #expect(EventFormatting.myStatus(event(mine: .requested, at: past), now: later) == "Demande restée sans réponse")
    #expect(EventFormatting.myStatus(event(at: past), organizerIsMe: true, now: later) == "Vous organisiez")
}

@Test func onlyAFutureOpenEventCanBeRequested() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(EventFormatting.canRequest(event(), now: now))
    #expect(EventFormatting.canRequest(event(mine: .withdrawn), now: now), "se retirer n'interdit pas de redemander")
    #expect(!EventFormatting.canRequest(event(mine: .requested), now: now))
    #expect(!EventFormatting.canRequest(event(mine: .accepted), now: now))
    #expect(!EventFormatting.canRequest(event(humans: 1, humansIn: 1), now: now), "complète")
    #expect(!EventFormatting.canRequest(event(status: .cancelled), now: now))
    #expect(!EventFormatting.canRequest(event(at: now.addingTimeInterval(-60)), now: now), "passée")
}

@Test func theDayIsCapitalisedInFrench() throws {
    // Noon, so the day is the same in every time zone: 10 October 2026 is a Saturday.
    var parts = DateComponents(year: 2026, month: 10, day: 10, hour: 12)
    parts.calendar = Calendar(identifier: .gregorian)
    let saturday = try #require(parts.date)
    #expect(EventFormatting.day(saturday) == "Samedi 10 octobre")
}
