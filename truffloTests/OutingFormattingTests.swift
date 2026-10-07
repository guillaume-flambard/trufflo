import Foundation
import Testing
@testable import trufflo

private func outing(humans: Int = 4, humansIn: Int = 1, dogs: Int = 3, dogsIn: Int = 1,
                   status: OutingStatus = .published, mine: ParticipationStatus? = nil,
                   at: Date = Date(timeIntervalSince1970: 2_000_000)) -> OutingDTO {
    OutingDTO(id: UUID(), organizerID: UUID(), organizerName: "Léa", zoneID: "z", startsAt: at, durationMinutes: 60,
                 meetingPoint: "Entrée nord", rules: "", humanCapacity: humans, dogCapacity: dogs,
                 humansAccepted: humansIn, dogsAccepted: dogsIn, status: status, myStatus: mine)
}

@Test(arguments: [(45, "45 min"), (60, "1 h"), (90, "1 h 30"), (125, "2 h 05")])
func durationReadsInFrench(_ minutes: Int, _ expected: String) {
    #expect(OutingFormatting.duration(minutes) == expected)
}

@Test func placesLeftAreCountedFromWhatIsAccepted() {
    #expect(OutingFormatting.places(outing()) == "3 places, 2 places pour des chiens")
    #expect(OutingFormatting.places(outing(humans: 2, humansIn: 1, dogs: 2, dogsIn: 1)) == "1 place, 1 place pour un chien")
    #expect(OutingFormatting.places(outing(humans: 2, humansIn: 2)) == "Complète")
    #expect(OutingFormatting.places(outing(dogs: 1, dogsIn: 1)) == "3 places, plus de place pour les chiens")
}

@Test func myOwnRequestIsSaidInWords() {
    // The default outing is in 1970: « now » is set before it, so it is still to come.
    let before = Date(timeIntervalSince1970: 1_000_000)
    func said(_ outing: OutingDTO, organizer: Bool = false) -> String? {
        OutingFormatting.myStatus(outing, organizerIsMe: organizer, now: before)
    }
    #expect(said(outing(mine: .requested)) == "Demande envoyée")
    #expect(said(outing(mine: .accepted)) == "Vous venez")
    #expect(said(outing(mine: .declined)) == "Demande refusée")
    #expect(said(outing(mine: .withdrawn)) == nil)
    #expect(said(outing(), organizer: true) == "Vous organisez")
    #expect(said(outing(status: .cancelled, mine: .accepted)) == "Annulée")
}

@Test func afterTheWalkTheTenseChangesAndAttendanceIsSaid() {
    let past = Date(timeIntervalSince1970: 1_000_000)
    let later = past.addingTimeInterval(3 * 3600)
    var accepted = outing(mine: .accepted, at: past)
    #expect(OutingFormatting.myStatus(accepted, now: later) == "Vous y étiez inscrit")
    accepted.myAttended = true
    #expect(OutingFormatting.myStatus(accepted, now: later) == "Vous y étiez")
    accepted.myAttended = false
    #expect(OutingFormatting.myStatus(accepted, now: later) == "Vous n'y étiez pas")
    #expect(OutingFormatting.myStatus(accepted, now: past.addingTimeInterval(-60)) == "Vous venez")
    #expect(OutingFormatting.myStatus(outing(mine: .requested, at: past), now: later) == "Demande restée sans réponse")
    #expect(OutingFormatting.myStatus(outing(at: past), organizerIsMe: true, now: later) == "Vous organisiez")
}

@Test func onlyAFutureOpenOutingCanBeRequested() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(OutingFormatting.canRequest(outing(), now: now))
    #expect(OutingFormatting.canRequest(outing(mine: .withdrawn), now: now), "se retirer n'interdit pas de redemander")
    #expect(!OutingFormatting.canRequest(outing(mine: .requested), now: now))
    #expect(!OutingFormatting.canRequest(outing(mine: .accepted), now: now))
    #expect(!OutingFormatting.canRequest(outing(humans: 1, humansIn: 1), now: now), "complète")
    #expect(!OutingFormatting.canRequest(outing(status: .cancelled), now: now))
    #expect(!OutingFormatting.canRequest(outing(at: now.addingTimeInterval(-60)), now: now), "passée")
}

@Test func theDayIsCapitalisedInFrench() throws {
    // Noon, so the day is the same in every time zone: 10 October 2026 is a Saturday.
    var parts = DateComponents(year: 2026, month: 10, day: 10, hour: 12)
    parts.calendar = Calendar(identifier: .gregorian)
    let saturday = try #require(parts.date)
    #expect(OutingFormatting.day(saturday) == "Samedi 10 octobre")
}
