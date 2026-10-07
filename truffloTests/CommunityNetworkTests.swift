import Foundation
import Testing
@testable import trufflo

// What can be checked about the community network layer without a server:
// the answers it will receive decode, and its failures become sentences. The
// calls themselves wait for the server (ADR 0010 « Contrat client »).

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try HouseholdCoding.decoder().decode(type, from: Data(json.utf8))
}

@Test("An outing row as PostgREST sends it decodes, dates in its two usual forms")
func anOutingRowDecodes() throws {
    let outing = try decode(OutingDTO.self, """
    {"id":"6f1f4b9e-0000-4000-8000-000000000001","organizer_id":"6f1f4b9e-0000-4000-8000-000000000002",
     "organizer_name":"Léa","zone_id":"lyon-6","starts_at":"2026-10-11T10:00:00+00:00","duration_minutes":60,
     "meeting_point":"Entrée nord du parc","rules":"","human_capacity":6,"dog_capacity":6,
     "humans_accepted":2,"dogs_accepted":3,"status":"published","my_status":"requested"}
    """)
    #expect(outing.meetingPoint == "Entrée nord du parc")
    #expect(outing.humanPlacesLeft == 4 && outing.dogPlacesLeft == 3)
    #expect(outing.myStatus == .requested)
    #expect(outing.myAttended == nil, "absent du JSON : pas encore déclaré")

    let spaced = try decode(OutingDTO.self, """
    {"id":"6f1f4b9e-0000-4000-8000-000000000001","organizer_id":"6f1f4b9e-0000-4000-8000-000000000002",
     "organizer_name":"Léa","zone_id":"lyon-6","starts_at":"2026-10-11 10:00:00.123456+00","duration_minutes":90,
     "meeting_point":"Parc","rules":"En laisse","human_capacity":4,"dog_capacity":4,
     "humans_accepted":0,"dogs_accepted":0,"status":"cancelled","my_status":null,"my_attended":false}
    """)
    #expect(spaced.status == .cancelled)
    #expect(spaced.myStatus == nil)
    #expect(spaced.myAttended == false)
    #expect(abs(spaced.startsAt.timeIntervalSince(outing.startsAt)) < 1)
}

@Test("Participants, updates, zones, dogs and blocked people decode")
func theOtherAnswersDecode() throws {
    let people = try decode([OutingParticipantDTO].self, """
    [{"user_id":"6f1f4b9e-0000-4000-8000-000000000003","display_name":"Camille","status":"accepted",
      "dog_names":["Oslo","Pixel"],"attended":true},
     {"user_id":"6f1f4b9e-0000-4000-8000-000000000004","display_name":"Sam","status":"requested","dog_names":[]}]
    """)
    #expect(people.map(\.displayName) == ["Camille", "Sam"])
    #expect(people[0].dogNames == ["Oslo", "Pixel"] && people[0].attended == true)
    #expect(people[1].attended == nil, "la présence n'est pas montrée à un participant")

    let updates = try decode([OutingUpdateDTO].self, """
    [{"id":"6f1f4b9e-0000-4000-8000-000000000010","outing_id":"6f1f4b9e-0000-4000-8000-000000000001",
      "kind":"place","previous":"Entrée nord","current":"Sortie ouest","created_at":"2026-10-07T09:00:00Z"}]
    """)
    #expect(updates.first?.kind == .place && updates.first?.current == "Sortie ouest")

    #expect(try decode([CommunityZone].self, #"[{"id":"lyon-6","name":"Lyon 6e"}]"#) == [CommunityZone(id: "lyon-6", name: "Lyon 6e")])

    let dog = try decode([CommunityDogDTO].self, """
    [{"id":"6f1f4b9e-0000-4000-8000-000000000020","owner_id":"6f1f4b9e-0000-4000-8000-000000000003",
      "name":"Oslo","breed_label":"","public_note":""}]
    """)
    #expect(dog.first?.name == "Oslo")

    let blocked = try decode([BlockedPersonDTO].self, """
    [{"user_id":"6f1f4b9e-0000-4000-8000-000000000005","display_name":"Marc"}]
    """)
    #expect(blocked.first?.displayName == "Marc")
}

@Test("A scalar answer, as create_outing returns, decodes to an identifier")
func aBareIdentifierDecodes() throws {
    let id = try decode(UUID.self, #""6f1f4b9e-0000-4000-8000-000000000001""#)
    #expect(id.uuidString.lowercased() == "6f1f4b9e-0000-4000-8000-000000000001")
}

@Test("Network failures become the community's errors, and the server's refusals keep their meaning")
func failuresAreTranslated() {
    #expect(CommunityError(RemoteError.signedOut) == .signedOut)
    #expect(CommunityError(RemoteError.offline) == .offline)
    #expect(CommunityError(RemoteError.forbidden("42501")) == .notAllowed)
    #expect(CommunityError(RemoteError.rejected("outing full")) == .outingFull)
    #expect(CommunityError(RemoteError.rejected("outing gone")) == .outingGone)
    #expect(CommunityError(RemoteError.rejected("you are blocked")) == .blocked)
    #expect(CommunityError(RemoteError.rejected("no profile")) == .noProfile)
    #expect(CommunityError(RemoteError.server(503)) == .network("HTTP 503"))
}

@MainActor
@Test("A signed-out person is asked to sign in, not shown a failure")
func signedOutAsksToSignIn() async throws {
    let server = InMemoryCommunityServer()
    server.addZone(CommunityZone(id: "z", name: "Z"))
    server.failure = .signedOut
    let model = CommunityModel(remote: server.client(UUID()))
    await model.refresh()
    #expect(model.phase == .needsSignIn)
    #expect(CommunityModel.message(for: CommunityError.signedOut) == "Votre session a expiré. Reconnectez-vous avec Apple.")
    #expect(CommunityModel.message(for: CommunityError.offline).hasPrefix("Pas de connexion"))
}

@Test("The real server stays closed until it is ready")
func theBackendIsClosedForNow() {
    // Flipping this is a decision (D5, D6, a published contact, the server's
    // own tests), not a side effect of merging the network layer.
    #expect(CommunityBackend.isOpen == false)
}
