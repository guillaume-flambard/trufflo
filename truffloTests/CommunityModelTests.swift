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
    let draft = try OutingDraft(startsAt: now.addingTimeInterval(86400), durationMinutes: 60, meetingPoint: "Entrée nord",
                                   rules: "", humanCapacity: 1, dogCapacity: 2, now: now)
    return (server, try await server.client(organizer).createOuting(draft, zoneID: lyon.id))
}

@MainActor
@Test("Without a profile the model asks for one, and nothing of the zone is loaded")
func noProfileMeansNoOutings() async throws {
    let (server, _) = try await world()
    let model = CommunityModel(remote: server.client(camille))
    await model.refresh()
    #expect(model.phase == .needsProfile)
    #expect(model.outings.isEmpty)
    #expect(model.zones.map(\.name) == ["Lyon 6e"])
}

@MainActor
@Test("Creating the profile loads the zone's outings; the adult declaration is required")
func theProfileOpensTheZone() async throws {
    let (server, outingID) = try await world()
    let model = CommunityModel(remote: server.client(camille))
    await model.refresh()

    await model.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: false)
    #expect(model.phase == .needsProfile)
    #expect(model.errorMessage == "Le pilote est réservé aux adultes.")

    await model.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    #expect(model.phase == .ready)
    #expect(model.outings.map(\.id) == [outingID])
    #expect(model.zoneName == "Lyon 6e")
    #expect(model.isOrganizer == false)
}

@MainActor
@Test("A request shows as pending, then a refusal for a full outing is said in words")
func requestingAndTheFullMessage() async throws {
    let (server, outingID) = try await world()
    let model = CommunityModel(remote: server.client(camille))
    await model.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    await model.requestToJoin(outingID, dogIDs: [])
    #expect(model.outing(outingID)?.myStatus == .requested)
    #expect(model.myOutings.map(\.id) == [outingID])

    // The organizer fills the only place; a later acceptance is refused.
    let sam = UUID()
    try await server.client(sam).saveProfile(displayName: "Sam", zoneID: lyon.id, adultDeclared: true)
    try await server.client(sam).requestToJoin(outingID: outingID, dogIDs: [])
    try await server.client(organizer).decide(outingID: outingID, userID: sam, accept: true)
    let boss = CommunityModel(remote: server.client(organizer))
    await boss.refresh()
    await boss.decide(outingID, userID: camille, accept: true)
    #expect(boss.errorMessage == "La sortie est complète.")
}

@MainActor
@Test("A suspended profile falls back to the profile step, without leaking the outings")
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
    #expect(CommunityError(serverMessage: "outing full") == .outingFull)
    #expect(CommunityError(serverMessage: "ERROR: outing gone") == .outingGone)
    #expect(CommunityError(serverMessage: "you are blocked") == .blocked)
    #expect(CommunityError(serverMessage: "no profile") == .noProfile)
    #expect(CommunityError(serverMessage: "not allowed") == .notAllowed)
    #expect(CommunityError(serverMessage: "weird") == .network("weird"))
}

@MainActor
@Test("An accepted request moves the revision, so an open outing reloads its participants")
func decidingMovesTheRevision() async throws {
    let (server, outingID) = try await world()
    try await server.client(camille).saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    try await server.client(camille).requestToJoin(outingID: outingID, dogIDs: [])
    let boss = CommunityModel(remote: server.client(organizer))
    await boss.refresh()
    #expect(await boss.participants(of: outingID).map(\.status) == [.requested])

    let before = boss.revision
    await boss.decide(outingID, userID: camille, accept: true)
    #expect(boss.revision > before)
    #expect(await boss.participants(of: outingID).map(\.status) == [.accepted])
}

@MainActor
@Test("An organizer creates, reschedules and cancels; the registered see each change")
func theOrganizerFlow() async throws {
    let (server, outingID) = try await world()
    let boss = CommunityModel(remote: server.client(organizer))
    await boss.refresh()
    #expect(boss.isOrganizer)

    let draft = try OutingDraft(startsAt: now.addingTimeInterval(3 * 86400), durationMinutes: 90, meetingPoint: "Quai nord",
                                   rules: "En laisse", humanCapacity: 5, dogCapacity: 5, now: now)
    let created = try #require(await boss.createOuting(draft))
    #expect(boss.outing(created)?.meetingPoint == "Quai nord")
    #expect(boss.myOutings.contains { $0.id == created })

    // Someone registers on the first outing, then the place changes.
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    await guest.requestToJoin(outingID, dogIDs: [])
    await boss.decide(outingID, userID: camille, accept: true)
    await boss.updateOuting(outingID, startsAt: now.addingTimeInterval(86400), meetingPoint: "  Sortie ouest  ")
    #expect(boss.outing(outingID)?.meetingPoint == "Sortie ouest", "le lieu est nettoyé")
    #expect(await guest.updates(of: outingID).map(\.kind) == [.place])

    await boss.cancelOuting(outingID)
    #expect(boss.outing(outingID)?.status == .cancelled)
    #expect(await guest.updates(of: outingID).map(\.kind).contains(.cancelled))
    await guest.refresh()
    #expect(guest.outings.contains { $0.id == outingID } == false, "une sortie annulée quitte la liste « à venir »")
    #expect(OutingFormatting.myStatus(try #require(guest.outing(outingID))) == "Annulée")
}

@MainActor
@Test("A person who is not an organizer cannot create, and is told so")
func aGuestCannotOrganize() async throws {
    let (server, _) = try await world()
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    #expect(guest.isOrganizer == false)
    let draft = try OutingDraft(startsAt: now.addingTimeInterval(86400), durationMinutes: 60, meetingPoint: "Parc",
                                   rules: "", humanCapacity: 3, dogCapacity: 3, now: now)
    #expect(await guest.createOuting(draft) == nil)
    #expect(guest.errorMessage == "Action non autorisée.")
}

@MainActor
@Test("After the walk, a registered person says whether they were there; the organizer sees it")
func attendanceIsDeclaredAfterTheWalk() async throws {
    let (server, outingID) = try await world()
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    await guest.requestToJoin(outingID, dogIDs: [])
    try await server.client(organizer).decide(outingID: outingID, userID: camille, accept: true)
    await guest.refresh()
    #expect(guest.outing(outingID)?.myAttended == nil)

    // Too early: refused, said in words, nothing recorded.
    await guest.declareAttendance(outingID, attended: true)
    #expect(guest.errorMessage == "Action non autorisée.")

    server.clock = { now.addingTimeInterval(86400 + 3 * 3600) }
    await guest.declareAttendance(outingID, attended: true)
    #expect(guest.outing(outingID)?.myAttended == true)
    let seen = try await server.client(organizer).participants(outingID: outingID).first
    #expect(seen?.attended == true)
    #expect(seen?.status == .accepted)
}

@MainActor
@Test("Blocking the organizer hides their outings; the blocked list can undo it")
func blockingIsUndoable() async throws {
    let (server, outingID) = try await world()
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    #expect(guest.outings.map(\.id) == [outingID])

    await guest.block(organizer)
    #expect(guest.outings.isEmpty)
    #expect(guest.blocked.map(\.displayName) == ["Léa"])

    await guest.unblock(organizer)
    #expect(guest.blocked.isEmpty)
    #expect(guest.outings.map(\.id) == [outingID])
}

@MainActor
@Test("A report is filed once and the person is told it went through")
func reportingReturnsTrue() async throws {
    let (server, outingID) = try await world()
    let guest = CommunityModel(remote: server.client(camille))
    await guest.saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    #expect(await guest.report(.outing, id: outingID, reason: .danger, detail: "Point de rendez-vous isolé"))
    #expect(server.reports.count == 1)
    #expect(server.reports.first?.reason == .danger)
    // Without a profile the report is refused and says so.
    let nobody = CommunityModel(remote: server.client(UUID()))
    #expect(await nobody.report(.outing, id: outingID, reason: .spam, detail: "") == false)
}

@Test("The public contact is not configured yet, and the pilot says so")
func theContactIsAnOpenItem() {
    // C-REQ-09: Apple asks for published contact information. Until decision D6
    // names it, this stays false and the pilot is not opened to the public.
    #expect(CommunityContact.isConfigured == false)
}
