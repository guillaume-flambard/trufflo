import Foundation
import SwiftData
import Testing
@testable import trufflo

// The household synchronisation (chantier 3, spec S1 to S14) against an
// in-memory server that enforces the same rules as the real one.

@MainActor
private struct Phone {
    let container: ModelContainer
    let repository: JournalRepository
    let sync: HouseholdSync
    var context: ModelContext { container.mainContext }

    init(server: FakeHouseholdServer, user: UUID) throws {
        container = try PersistenceFactory.make(inMemory: true)
        repository = JournalRepository(context: container.mainContext)
        sync = HouseholdSync(context: container.mainContext, remote: server.client(user),
                             now: { Date(timeIntervalSince1970: 2_000_000) })
    }

    @discardableResult
    func manualWalk(_ dogs: [UUID], minutes: Double, note: String = "", endedAt: Date = Date(timeIntervalSince1970: 1_900_000)) throws -> WalkRecord {
        try repository.addManualWalk(try ManualWalkInput(dogIDs: dogs, durationSeconds: minutes * 60, note: note),
                                     endedAt: endedAt)
    }

    func shared() throws -> [SharedWalkRecord] { try context.fetch(FetchDescriptor<SharedWalkRecord>()) }
}

private let anne = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
private let bruno = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

@MainActor
@Test func withoutAHouseholdNothingLeavesTheIPhone() async throws {
    let server = FakeHouseholdServer()
    let phone = try Phone(server: server, user: anne)
    let dog = try phone.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    try phone.manualWalk([dog.id], minutes: 30, note: "Parc")

    let report = try await phone.sync.sync()

    #expect(report.skippedNoHousehold)
    #expect(server.calls.isEmpty, "aucun appel réseau sans foyer : \(server.calls)")
    #expect(phone.sync.state(ofWalk: try #require(phone.repository.walk(id: try phone.context.fetch(FetchDescriptor<WalkRecord>())[0].id)).id) == .localOnly)
}

@Test func theWalkSummaryCarriesNoNoteNoPlaceNoPhoto() throws {
    let push = WalkPush(
        walk: WalkSummaryDTO(id: UUID(), householdID: UUID(), source: "gps", quality: "gpsRecorded",
                             startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1800),
                             confirmedSeconds: 1800, recordedPathMeters: 2140, correctedAt: nil),
        dogs: [WalkDogDTO(walkID: UUID(), dogID: UUID(), dogNameSnapshot: "Oslo")])
    let json = String(decoding: try HouseholdCoding.encoder().encode(push), as: UTF8.self).lowercased()
    for forbidden in ["note", "latitude", "longitude", "photo", "accuracy", "track", "point"] {
        #expect(!json.contains(forbidden), "« \(forbidden) » ne doit jamais partir : \(json)")
    }
    let dog = DogDTO(id: UUID(), householdID: UUID(), name: "Oslo", breedKind: "mixed", breedLabel: "", ageDescription: "3 ans")
    let dogJSON = String(decoding: try HouseholdCoding.encoder().encode(dog), as: UTF8.self).lowercased()
    for forbidden in ["photo", "gender", "preferences", "note"] {
        #expect(!dogJSON.contains(forbidden), "« \(forbidden) » ne doit jamais partir : \(dogJSON)")
    }
}

@MainActor
@Test func creatingAHouseholdSharesTheJournalOnceAndOnlyOnce() async throws {
    let server = FakeHouseholdServer()
    let phone = try Phone(server: server, user: anne)
    let dog = try phone.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    try phone.manualWalk([dog.id], minutes: 30)

    let first = try await phone.sync.createHousehold(name: "Maison", displayName: "Anne")
    #expect(first.dogsSent == 1)
    #expect(first.walksSent == 1)
    #expect(server.walks.count == 1)
    #expect(server.walks.values.first?.dogs.map(\.dogID) == [dog.id])

    server.resetCalls()
    let second = try await phone.sync.sync()
    #expect(second.walksSent == 0 && second.dogsSent == 0)
    #expect(!server.calls.contains("upsertWalk") && !server.calls.contains("upsertDog"),
            "une synchro sans changement ne renvoie rien : \(server.calls)")
}

@MainActor
@Test func aSessionStillRunningIsNotShared() async throws {
    let server = FakeHouseholdServer()
    let phone = try Phone(server: server, user: anne)
    let dog = try phone.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let live = try phone.repository.startGpsSession(dogIDs: [dog.id])

    try await phone.sync.createHousehold(name: "Maison", displayName: "Anne")

    #expect(server.walks[live.id] == nil)
}

@MainActor
@Test func aCorrectionIsSentOnceWithItsParticipants() async throws {
    let server = FakeHouseholdServer()
    let phone = try Phone(server: server, user: anne)
    let oslo = try phone.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let mira = try phone.repository.addDog(try DogInput(name: "Mirabelle", breedKind: "unknown"))
    let walk = try phone.manualWalk([oslo.id], minutes: 30)
    try await phone.sync.createHousehold(name: "Maison", displayName: "Anne")

    try phone.repository.correctWalk(walk.id, with: try WalkCorrection(
        dogIDs: [oslo.id, mira.id], note: "", durationSeconds: 45 * 60))
    server.resetCalls()
    let report = try await phone.sync.sync()

    #expect(report.walksSent == 1)
    let stored = try #require(server.walks[walk.id])
    #expect(stored.summary.confirmedSeconds == 45 * 60)
    #expect(Set(stored.dogs.map(\.dogID)) == [oslo.id, mira.id])
    #expect(stored.summary.correctedAt != nil)
    #expect(server.calls.filter { $0 == "upsertWalk" }.count == 1)
}

@MainActor
@Test func aDeletedWalkLeavesAsATombstoneAndNeverComesBack() async throws {
    let server = FakeHouseholdServer()
    let phone = try Phone(server: server, user: anne)
    let dog = try phone.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let walk = try phone.manualWalk([dog.id], minutes: 30)
    try await phone.sync.createHousehold(name: "Maison", displayName: "Anne")

    try phone.repository.deleteWalk(walk.id)
    let report = try await phone.sync.sync()
    #expect(report.tombstonesSent == 1)
    #expect(server.walks[walk.id]?.deletedAt != nil)

    server.resetCalls()
    try await phone.sync.sync()
    try await phone.sync.sync()
    #expect(!server.calls.contains("tombstoneWalk"), "le marqueur ne part qu'une fois")
    #expect(!server.calls.contains("upsertWalk"), "une balade supprimée n'est jamais renvoyée vivante")
    #expect(phone.repository.walk(id: walk.id) == nil)
}

@MainActor
@Test func aFailedSendChangesNoLocalDataAndKeepsWaiting() async throws {
    let server = FakeHouseholdServer()
    let phone = try Phone(server: server, user: anne)
    let dog = try phone.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    try await phone.sync.createHousehold(name: "Maison", displayName: "Anne")
    let walk = try phone.manualWalk([dog.id], minutes: 20, note: "Pluie")

    server.failure = .offline
    await #expect(throws: RemoteError.offline) { try await phone.sync.sync() }

    let local = try #require(phone.repository.walk(id: walk.id))
    #expect(local.confirmedSeconds == 20 * 60 && local.note == "Pluie" && local.revision == walk.revision)
    #expect(phone.sync.state(ofWalk: walk.id) == .pending)
    #expect(phone.sync.household()?.lastError == RemoteError.offline.message)

    server.failure = nil
    try await phone.sync.sync()
    #expect(phone.sync.state(ofWalk: walk.id) == .synced)
    #expect(phone.sync.household()?.lastError == nil)
}

@MainActor
@Test func joiningLinksDogsSharesWalksBothWaysAndNeverDuplicatesMine() async throws {
    let server = FakeHouseholdServer()
    let anneHome = try Phone(server: server, user: anne)
    let osloA = try anneHome.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let anneWalk = try anneHome.manualWalk([osloA.id], minutes: 30)
    try await anneHome.sync.createHousehold(name: "Maison", displayName: "Anne")
    let token = try await anneHome.sync.createInvite(role: .contributor)

    // Bruno has his own "Oslo" (the same dog) and his own "Pixel".
    let brunoHome = try Phone(server: server, user: bruno)
    let osloB = try brunoHome.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let pixel = try brunoHome.repository.addDog(try DogInput(name: "Pixel", breedKind: "unknown"))
    let brunoWalk = try brunoHome.manualWalk([osloB.id, pixel.id], minutes: 40)

    let (joined, dogs) = try await brunoHome.sync.acceptInvite(token: token)
    #expect(dogs.map(\.id) == [osloA.id])
    let report = try await brunoHome.sync.completeJoin(joined, displayName: "Bruno",
                                                        links: [osloB.id: osloA.id, pixel.id: nil])

    // Bruno's Oslo is Anne's Oslo: not recreated; Pixel enters as itself.
    #expect(server.dogs.keys.sorted { $0.uuidString < $1.uuidString } == [osloA.id, pixel.id].sorted { $0.uuidString < $1.uuidString })
    #expect(Set(try #require(server.walks[brunoWalk.id]).dogs.map(\.dogID)) == [osloA.id, pixel.id])
    #expect(report.walksReceived == 1)
    #expect(try brunoHome.shared().map(\.id) == [anneWalk.id])
    #expect(try brunoHome.shared().first?.dogNames == ["Oslo"])

    try await anneHome.sync.sync()
    #expect(try anneHome.shared().map(\.id) == [brunoWalk.id], "Anne reçoit la balade de Bruno, pas la sienne en double")
    let members = try anneHome.context.fetch(FetchDescriptor<HouseholdMemberRecord>())
    #expect(Set(members.map(\.displayName)) == ["Anne", "Bruno"])
}

@MainActor
@Test func aTombstoneReceivedRemovesTheCopyAndAnUpdateReplacesIt() async throws {
    let server = FakeHouseholdServer()
    let anneHome = try Phone(server: server, user: anne)
    let oslo = try anneHome.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let kept = try anneHome.manualWalk([oslo.id], minutes: 30)
    let removed = try anneHome.manualWalk([oslo.id], minutes: 15, endedAt: Date(timeIntervalSince1970: 1_800_000))
    try await anneHome.sync.createHousehold(name: "Maison", displayName: "Anne")
    let token = try await anneHome.sync.createInvite(role: .reader)

    let brunoHome = try Phone(server: server, user: bruno)
    let (joined, _) = try await brunoHome.sync.acceptInvite(token: token)
    try await brunoHome.sync.completeJoin(joined, displayName: "Bruno", links: [:])
    #expect(try brunoHome.shared().count == 2)

    try anneHome.repository.deleteWalk(removed.id)
    try anneHome.repository.correctWalk(kept.id, with: try WalkCorrection(dogIDs: [oslo.id], note: "", durationSeconds: 50 * 60))
    try await anneHome.sync.sync()
    #expect(server.walks[kept.id]?.summary.confirmedSeconds == 3000.0)

    let report = try await brunoHome.sync.sync()
    #expect(report.walksRemoved == 1)
    let copies = try brunoHome.shared()
    #expect(copies.map(\.id) == [kept.id])
    #expect(copies.first?.confirmedSeconds == 3000.0)
}

@MainActor
@Test func aReaderSendsNothing() async throws {
    let server = FakeHouseholdServer()
    let anneHome = try Phone(server: server, user: anne)
    try await anneHome.sync.createHousehold(name: "Maison", displayName: "Anne")
    let token = try await anneHome.sync.createInvite(role: .reader)

    let brunoHome = try Phone(server: server, user: bruno)
    let dog = try brunoHome.repository.addDog(try DogInput(name: "Pixel", breedKind: "unknown"))
    try brunoHome.manualWalk([dog.id], minutes: 10)
    let (joined, _) = try await brunoHome.sync.acceptInvite(token: token)
    server.resetCalls()
    try await brunoHome.sync.completeJoin(joined, displayName: "Bruno", links: [dog.id: nil])

    #expect(!server.calls.contains("upsertWalk") && !server.calls.contains("upsertDog"))
    #expect(server.walks.isEmpty)
}

@MainActor
@Test func aRemovedMemberLosesWhatTheyReceivedAndKeepsTheirOwnJournal() async throws {
    let server = FakeHouseholdServer()
    let anneHome = try Phone(server: server, user: anne)
    let oslo = try anneHome.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    try anneHome.manualWalk([oslo.id], minutes: 30)
    try await anneHome.sync.createHousehold(name: "Maison", displayName: "Anne")
    let token = try await anneHome.sync.createInvite(role: .contributor)

    let brunoHome = try Phone(server: server, user: bruno)
    let pixel = try brunoHome.repository.addDog(try DogInput(name: "Pixel", breedKind: "unknown"))
    let own = try brunoHome.manualWalk([pixel.id], minutes: 25, note: "À moi")
    let (joined, _) = try await brunoHome.sync.acceptInvite(token: token)
    try await brunoHome.sync.completeJoin(joined, displayName: "Bruno", links: [pixel.id: nil])
    #expect(try brunoHome.shared().count == 1)

    // Anne removes Bruno on the server.
    try await server.client(anne).leave(householdID: joined.id, userID: bruno)
    let report = try await brunoHome.sync.sync()

    #expect(report.revoked)
    #expect(try brunoHome.shared().isEmpty)
    #expect(brunoHome.sync.household() == nil)
    #expect(try brunoHome.context.fetch(FetchDescriptor<HouseholdMemberRecord>()).isEmpty)
    #expect(try brunoHome.context.fetch(FetchDescriptor<SyncLedgerRecord>()).isEmpty)
    #expect(brunoHome.repository.walk(id: own.id)?.note == "À moi", "le journal propre reste intact")
    #expect(brunoHome.repository.dog(id: pixel.id) != nil)
}

@MainActor
@Test func leavingPurgesAndTheLastOwnerCannotLeave() async throws {
    let server = FakeHouseholdServer()
    let anneHome = try Phone(server: server, user: anne)
    try await anneHome.sync.createHousehold(name: "Maison", displayName: "Anne")
    await #expect(throws: RemoteError.self) { try await anneHome.sync.leave() }
    #expect(anneHome.sync.household() != nil, "un refus du serveur ne purge rien")

    let token = try await anneHome.sync.createInvite(role: .contributor)
    let brunoHome = try Phone(server: server, user: bruno)
    let (joined, _) = try await brunoHome.sync.acceptInvite(token: token)
    try await brunoHome.sync.completeJoin(joined, displayName: "Bruno", links: [:])
    try await brunoHome.sync.leave()
    #expect(brunoHome.sync.household() == nil)
    #expect(server.members[joined.id]?[bruno] == nil)
}

@Test func postgresTimestampsParseWithMicroseconds() {
    let date = HouseholdCoding.parse("2026-10-06T17:22:18.705123+00:00")
    #expect(date == Date(timeIntervalSince1970: 1_791_307_338.705))
    #expect(HouseholdCoding.parse("2026-10-06T17:22:18+00:00") == Date(timeIntervalSince1970: 1_791_307_338))
    #expect(HouseholdCoding.parse("2026-10-06T17:22:18.7Z") == Date(timeIntervalSince1970: 1_791_307_338.7))
}

@MainActor
@Test func aReinstalledIPhoneFindsItsHouseholdAndGetsItsSummariesBackReadOnly() async throws {
    let server = FakeHouseholdServer()
    let before = try Phone(server: server, user: anne)
    let oslo = try before.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let walk = try before.manualWalk([oslo.id], minutes: 30, note: "Privé")
    try await before.sync.createHousehold(name: "Maison", displayName: "Anne")

    // Same account, empty iPhone.
    let after = try Phone(server: server, user: anne)
    let found = try #require(try await after.sync.householdToResume())
    #expect(found.name == "Maison")
    let (household, dogs) = try await after.sync.resume(found)
    #expect(dogs.map(\.id) == [oslo.id])
    try await after.sync.completeJoin(household, displayName: "Anne", links: [:])

    let copies = try after.shared()
    #expect(copies.map(\.id) == [walk.id], "la synthèse revient, en lecture seule")
    #expect(after.sync.household()?.myRole == .owner)
}

@MainActor
@Test func aDeletedWalkWhoseTombstoneWasRefusedDoesNotComeBackAsACopy() async throws {
    let server = FakeHouseholdServer()
    let phone = try Phone(server: server, user: anne)
    let oslo = try phone.repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let walk = try phone.manualWalk([oslo.id], minutes: 30)
    try await phone.sync.createHousehold(name: "Maison", displayName: "Anne")
    try phone.repository.deleteWalk(walk.id)

    // The tombstone is refused for this item; the sync goes on and pulls.
    server.refuse = ["tombstoneWalk"]
    try await phone.sync.sync()
    #expect(server.walks[walk.id]?.deletedAt == nil)
    #expect(try phone.shared().isEmpty, "une balade supprimée ici ne revient pas en copie")
}

@MainActor
@Test func oneHouseholdAtATimeIsARefusalNotACrash() async throws {
    let server = FakeHouseholdServer()
    let phone = try Phone(server: server, user: anne)
    try await phone.sync.createHousehold(name: "Maison", displayName: "Anne")
    await #expect(throws: RemoteError.self) { try await phone.sync.createHousehold(name: "Autre", displayName: "Anne") }
    #expect(try await phone.sync.householdToResume() == nil)
}
