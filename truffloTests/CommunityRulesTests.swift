import Foundation
import Testing
@testable import trufflo

// The rules of ADR 0010 as the in-memory server applies them. They are what
// the client is built against, and the list the real server's pgTAP tests
// must also hold (C-AC-01, 05, 06, 08).

private let lyon = CommunityZone(id: "lyon-6", name: "Lyon 6e")
private let paris = CommunityZone(id: "paris-11", name: "Paris 11e")
private let now = Date(timeIntervalSince1970: 2_000_000)
private let organizer = UUID(), camille = UUID(), sam = UUID(), alex = UUID(), stranger = UUID()

private struct World {
    let server = InMemoryCommunityServer()
    var outingID = UUID()

    init(humans: Int = 3, dogs: Int = 3) async throws {
        server.clock = { now }
        server.addZone(lyon)
        server.addZone(paris)
        server.makeOrganizer(organizer, in: lyon.id)
        for (user, name) in [(organizer, "Léa"), (camille, "Camille"), (sam, "Sam"), (alex, "Alex")] {
            try await server.client(user).saveProfile(displayName: name, zoneID: lyon.id, adultDeclared: true)
        }
        try await server.client(stranger).saveProfile(displayName: "Zoé", zoneID: paris.id, adultDeclared: true)
        let draft = try OutingDraft(startsAt: now.addingTimeInterval(86400), durationMinutes: 60,
                                       meetingPoint: "Entrée nord du parc", rules: "En laisse près de l'étang",
                                       humanCapacity: humans, dogCapacity: dogs, now: now)
        outingID = try await server.client(organizer).createOuting(draft, zoneID: lyon.id)
    }

    func dog(_ owner: UUID, _ name: String) async throws -> UUID {
        let id = UUID()
        try await server.client(owner).saveDog(.init(id: id, ownerID: owner, name: name))
        return id
    }
}

@Test("C-AC-01: nobody without a valid profile sees anything, and a zone sees only its own outings")
func visibilityFollowsTheProfileAndTheZone() async throws {
    let world = try await World()
    let nobody = world.server.client(UUID())
    await #expect(throws: CommunityError.noProfile) { try await nobody.outings(zoneID: lyon.id) }

    #expect(try await world.server.client(camille).outings(zoneID: lyon.id).map(\.id) == [world.outingID])
    #expect(try await world.server.client(stranger).outings(zoneID: lyon.id).isEmpty, "une autre zone ne voit rien")

    world.server.suspend(sam)
    await #expect(throws: CommunityError.noProfile) { try await world.server.client(sam).outings(zoneID: lyon.id) }
}

@Test("A closed zone shows nothing and cannot be joined")
func aClosedZoneIsInvisible() async throws {
    let server = InMemoryCommunityServer()
    server.addZone(lyon, open: false)
    #expect(try await server.client(camille).zones().isEmpty)
    await #expect(throws: CommunityError.self) {
        try await server.client(camille).saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: true)
    }
}

@Test("Without the adult declaration there is no profile")
func theProfileNeedsTheAdultDeclaration() async throws {
    let server = InMemoryCommunityServer()
    server.addZone(lyon)
    await #expect(throws: CommunityError.self) {
        try await server.client(camille).saveProfile(displayName: "Camille", zoneID: lyon.id, adultDeclared: false)
    }
    #expect(try await server.client(camille).myProfile() == nil)
}

@Test("Participants are visible to the organizer and to accepted people only")
func participantsAreNotPublic() async throws {
    let world = try await World()
    let oslo = try await world.dog(camille, "Oslo")
    try await world.server.client(camille).requestToJoin(outingID: world.outingID, dogIDs: [oslo])
    try await world.server.client(sam).requestToJoin(outingID: world.outingID, dogIDs: [])

    await #expect(throws: CommunityError.notAllowed) { try await world.server.client(alex).participants(outingID: world.outingID) }
    await #expect(throws: CommunityError.notAllowed) { try await world.server.client(camille).participants(outingID: world.outingID) }
    #expect(try await world.server.client(organizer).participants(outingID: world.outingID).count == 2)

    try await world.server.client(organizer).decide(outingID: world.outingID, userID: camille, accept: true)
    let seen = try await world.server.client(camille).participants(outingID: world.outingID)
    #expect(seen.map(\.displayName) == ["Camille"], "un participant accepté ne voit que les acceptés")
    #expect(seen.first?.dogNames == ["Oslo"])
}

@Test("C-AC-05: two acceptances for the last place, only one passes")
func theLastPlaceGoesToOne() async throws {
    let world = try await World(humans: 1, dogs: 5)
    try await world.server.client(camille).requestToJoin(outingID: world.outingID, dogIDs: [])
    try await world.server.client(sam).requestToJoin(outingID: world.outingID, dogIDs: [])
    let boss = world.server.client(organizer)

    try await boss.decide(outingID: world.outingID, userID: camille, accept: true)
    await #expect(throws: CommunityError.outingFull) { try await boss.decide(outingID: world.outingID, userID: sam, accept: true) }
    let outing = try await world.server.client(alex).outings(zoneID: lyon.id).first
    #expect(outing?.humanPlacesLeft == 0)
}

@Test("The dog capacity is checked as well as the human one")
func dogsHaveTheirOwnCapacity() async throws {
    let world = try await World(humans: 5, dogs: 1)
    let oslo = try await world.dog(camille, "Oslo"), pixel = try await world.dog(sam, "Pixel")
    try await world.server.client(camille).requestToJoin(outingID: world.outingID, dogIDs: [oslo])
    try await world.server.client(sam).requestToJoin(outingID: world.outingID, dogIDs: [pixel])
    try await world.server.client(organizer).decide(outingID: world.outingID, userID: camille, accept: true)
    await #expect(throws: CommunityError.outingFull) {
        try await world.server.client(organizer).decide(outingID: world.outingID, userID: sam, accept: true)
    }
}

@Test("C-AC-06: being registered and having attended are two different states")
func inscriptionIsNotAttendance() async throws {
    let world = try await World()
    try await world.server.client(camille).requestToJoin(outingID: world.outingID, dogIDs: [])
    try await world.server.client(organizer).decide(outingID: world.outingID, userID: camille, accept: true)

    // Before the walk is over, attendance cannot be declared.
    await #expect(throws: CommunityError.notAllowed) { try await world.server.client(camille).declareAttendance(outingID: world.outingID, attended: true) }

    world.server.clock = { now.addingTimeInterval(86400 + 3 * 3600) }
    try await world.server.client(camille).declareAttendance(outingID: world.outingID, attended: false)
    let mine = try await world.server.client(organizer).participants(outingID: world.outingID).first
    #expect(mine?.status == .accepted, "l'inscription reste acceptée")
    #expect(mine?.attended == false, "la présence est déclarée à part")
    // Someone who was never accepted cannot declare a presence.
    await #expect(throws: CommunityError.notAllowed) { try await world.server.client(alex).declareAttendance(outingID: world.outingID, attended: true) }
}

@Test("C-AC-08: a block hides outings and requests in both directions")
func aBlockWorksBothWays() async throws {
    let world = try await World()
    try await world.server.client(camille).block(userID: organizer)
    #expect(try await world.server.client(camille).outings(zoneID: lyon.id).isEmpty, "le bloqueur ne voit plus ses sorties")
    await #expect(throws: CommunityError.blocked) { try await world.server.client(camille).requestToJoin(outingID: world.outingID, dogIDs: []) }

    try await world.server.client(sam).block(userID: organizer)
    try await world.server.client(organizer).unblock(userID: camille) // not a block of his: nothing changes
    #expect(try await world.server.client(sam).outings(zoneID: lyon.id).isEmpty)

    // Unblocking restores the view.
    try await world.server.client(camille).unblock(userID: organizer)
    #expect(try await world.server.client(camille).outings(zoneID: lyon.id).count == 1)
}

@Test("Only a registered organizer creates an outing, and a participant cannot decide")
func onlyOrganizersOrganize() async throws {
    let world = try await World()
    let draft = try OutingDraft(startsAt: now.addingTimeInterval(7200), durationMinutes: 45, meetingPoint: "Place",
                                   rules: "", humanCapacity: 4, dogCapacity: 4, now: now)
    await #expect(throws: CommunityError.notAllowed) { try await world.server.client(camille).createOuting(draft, zoneID: lyon.id) }
    try await world.server.client(camille).requestToJoin(outingID: world.outingID, dogIDs: [])
    await #expect(throws: CommunityError.notAllowed) {
        try await world.server.client(sam).decide(outingID: world.outingID, userID: camille, accept: true)
    }
    #expect(try await world.server.client(organizer).isOrganizer(zoneID: lyon.id))
    #expect(try await world.server.client(camille).isOrganizer(zoneID: lyon.id) == false)
}

@Test("A change of time or place is told to the registered, who can withdraw")
func changesAreVisibleAndWithdrawalFreesThePlace() async throws {
    let world = try await World(humans: 1, dogs: 5)
    try await world.server.client(camille).requestToJoin(outingID: world.outingID, dogIDs: [])
    try await world.server.client(organizer).decide(outingID: world.outingID, userID: camille, accept: true)

    try await world.server.client(organizer).updateOuting(outingID: world.outingID, startsAt: now.addingTimeInterval(90000),
                                                         meetingPoint: "Sortie ouest du parc")
    let told = try await world.server.client(camille).updates(outingID: world.outingID)
    #expect(Set(told.map(\.kind)) == [.time, .place])
    await #expect(throws: CommunityError.notAllowed) { try await world.server.client(alex).updates(outingID: world.outingID) }

    try await world.server.client(camille).withdraw(outingID: world.outingID)
    let outing = try await world.server.client(alex).outings(zoneID: lyon.id).first
    #expect(outing?.humanPlacesLeft == 1, "se retirer libère la place")
}

@Test("The draft refuses what the server refuses")
func theDraftValidates() {
    func make(_ minutes: Int = 60, _ point: String = "Parc", _ humans: Int = 3, at: Date = now.addingTimeInterval(3600)) throws {
        _ = try OutingDraft(startsAt: at, durationMinutes: minutes, meetingPoint: point, rules: "", humanCapacity: humans, dogCapacity: 3, now: now)
    }
    #expect(throws: CommunityError.self) { try make(at: now.addingTimeInterval(-60)) }
    #expect(throws: CommunityError.self) { try make(10) }
    #expect(throws: CommunityError.self) { try make(300) }
    #expect(throws: CommunityError.self) { try make(60, "   ") }
    #expect(throws: CommunityError.self) { try make(60, "Parc", 0) }
    #expect(throws: CommunityError.self) { try make(60, "Parc", 31) }
    #expect((try? make()) != nil)
}
