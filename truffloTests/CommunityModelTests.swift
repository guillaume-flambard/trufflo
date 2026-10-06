import Foundation
import Testing
@testable import trufflo

private let lyon = CommunityZone(id: "lyon-6", name: "Lyon 6e")
private let now = Date(timeIntervalSince1970: 2_000_000)
private let organizer = UUID(), camille = UUID()

@MainActor
private func world() async throws -> (InMemoryCommunityServer, UUID) {
    let server = InMemoryCommunityServer()
    server.clock = { now }
    server.addZone(lyon)
    server.makeOrganizer(organizer, in: lyon.id)
    try await server.client(organizer).saveProfile(displayName: "Léa", zoneID: lyon.id, adultDeclared: true)
    let draft = try WalkEventDraft(startsAt: now.addingTimeInterval(86400), durationMinutes: 60, meetingPoint: "Entrée nord",
                                   rules: "", humanCapacity: 1, dogCapacity: 2, now: now)
    return (server, try await server.client(organizer).createEvent(draft, zoneID: lyon.id))
}

@MainActor
@Test("Without a profile the model asks for one, and nothing of the zone is loaded")
func noProfileMeansNoEvents() async throws {
    let (server, _) = try await world()
    let model = CommunityModel(remote: server.client(camille))
    await model.refresh()
    #expect(model.phase == .needsProfile)
    #expect(model.events.isEmpty)
    #expect(model.zones.map(\.name) == ["Lyon 6e"])
}

@MainActor
@Test("Creating the profile loads the zone's events; the adult declaration is required")
func theProfileOpensTheZone() async throws {
    let (server, eventID) = try await world()
    let model = CommunityModel(remote: server.client(camille))
    await model.refresh()

    await model.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: false)
    #expect(model.phase == .needsProfile)
    #expect(model.errorMessage == "Le pilote est réservé aux adultes.")

    await model.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    #expect(model.phase == .ready)
    #expect(model.events.map(\.id) == [eventID])
    #expect(model.zoneName == "Lyon 6e")
    #expect(model.isOrganizer == false)
}

@MainActor
@Test("A request shows as pending, then a refusal for a full event is said in words")
func requestingAndTheFullMessage() async throws {
    let (server, eventID) = try await world()
    let model = CommunityModel(remote: server.client(camille))
    await model.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    await model.requestToJoin(eventID, dogIDs: [])
    #expect(model.event(eventID)?.myStatus == .requested)
    #expect(model.myEvents.map(\.id) == [eventID])

    // The organizer fills the only place; a later acceptance is refused.
    let sam = UUID()
    try await server.client(sam).saveProfile(displayName: "Sam", zoneID: lyon.id, adultDeclared: true)
    try await server.client(sam).requestToJoin(eventID: eventID, dogIDs: [])
    try await server.client(organizer).decide(eventID: eventID, userID: sam, accept: true)
    let boss = CommunityModel(remote: server.client(organizer))
    await boss.refresh()
    await boss.decide(eventID, userID: camille, accept: true)
    #expect(boss.errorMessage == "La sortie est complète.")
}

@MainActor
@Test("A suspended profile falls back to the profile step, without leaking the events")
func suspendedMeansNoProfile() async throws {
    let (server, _) = try await world()
    let model = CommunityModel(remote: server.client(organizer))
    await model.refresh()
    #expect(model.phase == .ready)
    server.suspend(organizer)
    await model.refresh()
    #expect(model.phase == .needsProfile)
}

@MainActor
@Test("A server that does not answer gives a sentence, not a stack")
func aFailureIsReadable() async throws {
    let (server, _) = try await world()
    let model = CommunityModel(remote: server.client(camille))
    server.failure = .network("timeout 504")
    await model.refresh()
    #expect(model.phase == .failed("Le serveur n'a pas répondu. Réessayez."))
}

@Test("The server's own messages map to the client's errors")
func serverMessagesMap() {
    #expect(CommunityError(serverMessage: "event full") == .eventFull)
    #expect(CommunityError(serverMessage: "ERROR: event gone") == .eventGone)
    #expect(CommunityError(serverMessage: "you are blocked") == .blocked)
    #expect(CommunityError(serverMessage: "no profile") == .noProfile)
    #expect(CommunityError(serverMessage: "not allowed") == .notAllowed)
    #expect(CommunityError(serverMessage: "weird") == .network("weird"))
}

@MainActor
@Test("An accepted request moves the revision, so an open event reloads its participants")
func decidingMovesTheRevision() async throws {
    let (server, eventID) = try await world()
    try await server.client(camille).saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    try await server.client(camille).requestToJoin(eventID: eventID, dogIDs: [])
    let boss = CommunityModel(remote: server.client(organizer))
    await boss.refresh()
    #expect(await boss.participants(of: eventID).map(\.status) == [.requested])

    let before = boss.revision
    await boss.decide(eventID, userID: camille, accept: true)
    #expect(boss.revision > before)
    #expect(await boss.participants(of: eventID).map(\.status) == [.accepted])
}

@MainActor
@Test("An organizer creates, reschedules and cancels; the registered see each change")
func theOrganizerFlow() async throws {
    let (server, eventID) = try await world()
    let boss = CommunityModel(remote: server.client(organizer))
    await boss.refresh()
    #expect(boss.isOrganizer)

    let draft = try WalkEventDraft(startsAt: now.addingTimeInterval(3 * 86400), durationMinutes: 90, meetingPoint: "Quai nord",
                                   rules: "En laisse", humanCapacity: 5, dogCapacity: 5, now: now)
    let created = try #require(await boss.createEvent(draft))
    #expect(boss.event(created)?.meetingPoint == "Quai nord")
    #expect(boss.myEvents.contains { $0.id == created })

    // Someone registers on the first event, then the place changes.
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    await guest.requestToJoin(eventID, dogIDs: [])
    await boss.decide(eventID, userID: camille, accept: true)
    await boss.updateEvent(eventID, startsAt: now.addingTimeInterval(86400), meetingPoint: "  Sortie ouest  ")
    #expect(boss.event(eventID)?.meetingPoint == "Sortie ouest", "le lieu est nettoyé")
    #expect(await guest.updates(of: eventID).map(\.kind) == [.place])

    await boss.cancelEvent(eventID)
    #expect(boss.event(eventID)?.status == .cancelled)
    #expect(await guest.updates(of: eventID).map(\.kind).contains(.cancelled))
    await guest.refresh()
    #expect(guest.events.contains { $0.id == eventID } == false, "une sortie annulée quitte la liste « à venir »")
    #expect(EventFormatting.myStatus(try #require(guest.event(eventID))) == "Annulée")
}

@MainActor
@Test("A person who is not an organizer cannot create, and is told so")
func aGuestCannotOrganize() async throws {
    let (server, _) = try await world()
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    #expect(guest.isOrganizer == false)
    let draft = try WalkEventDraft(startsAt: now.addingTimeInterval(86400), durationMinutes: 60, meetingPoint: "Parc",
                                   rules: "", humanCapacity: 3, dogCapacity: 3, now: now)
    #expect(await guest.createEvent(draft) == nil)
    #expect(guest.errorMessage == "Action non autorisée.")
}

@MainActor
@Test("After the walk, a registered person says whether they were there; the organizer sees it")
func attendanceIsDeclaredAfterTheWalk() async throws {
    let (server, eventID) = try await world()
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    await guest.requestToJoin(eventID, dogIDs: [])
    try await server.client(organizer).decide(eventID: eventID, userID: camille, accept: true)
    await guest.refresh()
    #expect(guest.event(eventID)?.myAttended == nil)

    // Too early: refused, said in words, nothing recorded.
    await guest.declareAttendance(eventID, attended: true)
    #expect(guest.errorMessage == "Action non autorisée.")

    server.clock = { now.addingTimeInterval(86400 + 3 * 3600) }
    await guest.declareAttendance(eventID, attended: true)
    #expect(guest.event(eventID)?.myAttended == true)
    let seen = try await server.client(organizer).participants(eventID: eventID).first
    #expect(seen?.attended == true)
    #expect(seen?.status == .accepted)
}

@MainActor
@Test("Blocking the organizer hides their events; the blocked list can undo it")
func blockingIsUndoable() async throws {
    let (server, eventID) = try await world()
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    #expect(guest.events.map(\.id) == [eventID])

    await guest.block(organizer)
    #expect(guest.events.isEmpty)
    #expect(guest.blocked.map(\.displayName) == ["Léa"])

    await guest.unblock(organizer)
    #expect(guest.blocked.isEmpty)
    #expect(guest.events.map(\.id) == [eventID])
}

@MainActor
@Test("A report is filed once and the person is told it went through")
func reportingReturnsTrue() async throws {
    let (server, eventID) = try await world()
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    #expect(await guest.report(.event, id: eventID, reason: .danger, detail: "Point de rendez-vous isolé"))
    #expect(server.reports.count == 1)
    #expect(server.reports.first?.reason == .danger)
    // Without a profile the report is refused and says so.
    let nobody = CommunityModel(remote: server.client(UUID()))
    #expect(await nobody.report(.event, id: eventID, reason: .spam, detail: "") == false)
}

@Test("The public contact is not configured yet, and the pilot says so")
func theContactIsAnOpenItem() {
    // C-REQ-09: Apple asks for published contact information. Until decision D6
    // names it, this stays false and the pilot is not opened to the public.
    #expect(CommunityContact.isConfigured == false)
}
