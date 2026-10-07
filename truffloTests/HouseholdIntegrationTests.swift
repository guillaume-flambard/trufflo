import Foundation
import Supabase
import SwiftData
import Testing
@testable import trufflo

// The whole household journey, two people, over real HTTP against a local
// Supabase built from backend/supabase (chantier 3, AC-18). The production
// client runs unchanged; only the sign-in differs, since Apple cannot sign in
// a simulator test, so the two accounts are local email accounts.
//
// Off by default. Run with tools/backend/household-integration.sh, which
// starts the local stack, resets it and passes its address and anon key.

private enum Local {
    static let env = ProcessInfo.processInfo.environment
    static var url: URL? { env["TRUFFLO_LOCAL_API_URL"].flatMap(URL.init(string:)) }
    static var anonKey: String? { env["TRUFFLO_LOCAL_ANON_KEY"] }
    static var enabled: Bool { url != nil && anonKey != nil }
}

/// Signs up a fresh local account through the official SDK and returns the
/// production remote for it. The session lives in memory, never in the keychain.
private func account(_ config: BackendConfig) async throws -> SupabaseRemote {
    let client = config.makeClient(storage: MemoryAuthStorage())
    _ = try await client.auth.signUp(email: "\(UUID().uuidString.lowercased())@trufflo.test",
                                     password: UUID().uuidString)
    return SupabaseRemote(client: client)
}

@MainActor
@Test(.enabled(if: Local.enabled, "needs a local Supabase, see tools/backend/household-integration.sh"))
func twoPeopleShareAHouseholdOverRealHTTP() async throws {
    let config = BackendConfig(baseURL: try #require(Local.url), anonKey: try #require(Local.anonKey))
    let anneRemote = try await account(config)
    let brunoRemote = try await account(config)

    let anneStore = try PersistenceFactory.make(inMemory: true)
    let anne = JournalRepository(context: anneStore.mainContext)
    let anneSync = HouseholdSync(context: anneStore.mainContext, remote: anneRemote)
    let brunoStore = try PersistenceFactory.make(inMemory: true)
    let bruno = JournalRepository(context: brunoStore.mainContext)
    let brunoSync = HouseholdSync(context: brunoStore.mainContext, remote: brunoRemote)

    // Anne: a dog, a GPS-less walk with a private note, then a household.
    let osloA = try anne.addDog(try DogInput(name: "Oslo", breedKind: "mixed"))
    let anneWalk = try anne.addManualWalk(try ManualWalkInput(dogIDs: [osloA.id], durationSeconds: 1800, note: "Note privée"),
                                          endedAt: Date().addingTimeInterval(-7200))
    let created = try await anneSync.createHousehold(name: "Maison", displayName: "Anne")
    #expect(created.dogsSent == 1 && created.walksSent == 1)
    let token = try await anneSync.createInvite(role: .contributor)

    // Bruno: his own Oslo (the same dog) and Pixel; he joins and links Oslo.
    let osloB = try bruno.addDog(try DogInput(name: "Oslo", breedKind: "mixed"))
    let pixel = try bruno.addDog(try DogInput(name: "Pixel", breedKind: "unknown"))
    let brunoWalk = try bruno.addManualWalk(try ManualWalkInput(dogIDs: [osloB.id, pixel.id], durationSeconds: 2400, note: ""),
                                            endedAt: Date().addingTimeInterval(-3600))
    let (joined, dogs) = try await brunoSync.acceptInvite(token: token)
    #expect(joined.name == "Maison")
    #expect(dogs.map(\.id) == [osloA.id])
    let joinReport = try await brunoSync.completeJoin(joined, displayName: "Bruno", links: [osloB.id: osloA.id, pixel.id: nil])
    #expect(joinReport.walksSent == 1)
    #expect(joinReport.walksReceived == 1)
    let received = try brunoStore.mainContext.fetch(FetchDescriptor<SharedWalkRecord>())
    #expect(received.map(\.id) == [anneWalk.id])
    #expect(received.first?.dogNames == ["Oslo"])
    #expect(received.first?.recordedPathMeters == nil)

    // Anne receives Bruno's walk with both dogs, under the household's Oslo.
    try await anneSync.sync()
    let anneReceived = try anneStore.mainContext.fetch(FetchDescriptor<SharedWalkRecord>())
    #expect(anneReceived.map(\.id) == [brunoWalk.id])
    #expect(Set(anneReceived.first?.dogIDs ?? []) == [osloA.id, pixel.id])
    let names = try anneStore.mainContext.fetch(FetchDescriptor<HouseholdMemberRecord>()).map(\.displayName)
    #expect(Set(names) == ["Anne", "Bruno"])

    // Over real HTTP: the shared details, a planned walk, live positions.
    try anne.updateWalkDetails(anneWalk.id, title: "Tour du parc", mood: .calm, note: "privée")
    _ = try anne.planWalk(at: Date().addingTimeInterval(3600), placeName: "Parc", latitude: 48.88, longitude: 2.38)
    try await anneSync.sync()
    try await brunoSync.sync()
    let detailed = try brunoStore.mainContext.fetch(FetchDescriptor<SharedWalkRecord>())
    #expect(detailed.first?.title == "Tour du parc")
    #expect(detailed.first?.mood == .calm)
    #expect(try brunoStore.mainContext.fetch(FetchDescriptor<SharedPlannedWalkRecord>()).map(\.placeName) == ["Parc"])
    try await anneSync.shareLivePosition(latitude: 48.8812345, longitude: 2.3812345)
    try await anneSync.shareLivePosition(latitude: 48.8812345, longitude: 2.3812345)
    let seen = try await brunoSync.othersLivePositions()
    #expect(seen.count == 1, "une ligne par membre, réécrite")
    #expect(seen.first?.latitude == 48.8812, "arrondi par le serveur")
    try await anneSync.stopLivePosition()
    #expect(try await brunoSync.othersLivePositions().isEmpty)

    // A correction and a deletion travel; nothing comes back to life.
    try anne.correctWalk(anneWalk.id, with: try WalkCorrection(dogIDs: [osloA.id], note: "", durationSeconds: 2700))
    try await anneSync.sync()
    try await brunoSync.sync()
    #expect(try brunoStore.mainContext.fetch(FetchDescriptor<SharedWalkRecord>()).first?.confirmedSeconds == 2700.0)

    try anne.deleteWalk(anneWalk.id)
    try await anneSync.sync()
    let afterDelete = try await brunoSync.sync()
    #expect(afterDelete.walksRemoved == 1)
    #expect(try brunoStore.mainContext.fetch(FetchDescriptor<SharedWalkRecord>()).isEmpty)
    try await anneSync.sync()
    try await brunoSync.sync()
    #expect(try brunoStore.mainContext.fetch(FetchDescriptor<SharedWalkRecord>()).isEmpty, "une balade supprimée ne revient pas")

    // Anne on an empty iPhone, same account: the server tells her where she belongs.
    let anneAgainStore = try PersistenceFactory.make(inMemory: true)
    let anneAgain = HouseholdSync(context: anneAgainStore.mainContext, remote: anneRemote)
    let found = try #require(try await anneAgain.householdToResume())
    #expect(found.name == "Maison")
    let (resumed, _) = try await anneAgain.resume(found)
    try await anneAgain.completeJoin(resumed, displayName: "Anne", links: [:])
    #expect(anneAgain.household()?.myRole == .owner)
    #expect(Set(try anneAgainStore.mainContext.fetch(FetchDescriptor<SharedWalkRecord>()).map(\.id)) == [brunoWalk.id],
            "la balade supprimée ne revient pas, celle de Bruno oui")

    // The last owner cannot leave; Bruno leaves and loses access at once.
    await #expect(throws: RemoteError.self) { try await anneSync.leave() }
    let household = try #require(brunoSync.household())
    try await brunoSync.leave()
    #expect(brunoSync.household() == nil)
    #expect(try await brunoRemote.household(id: household.id) == nil, "retiré, le serveur ne lui montre plus rien")
    #expect(try await brunoRemote.walks(householdID: household.id, changedSince: nil).isEmpty)
    #expect(bruno.walk(id: brunoWalk.id) != nil, "son propre journal reste intact")
}

/// Live updates: a member hears about a household walk change; an outsider
/// subscribed to the same filter hears nothing (Realtime applies RLS).
@MainActor
@Test(.enabled(if: Local.enabled, "needs a local Supabase, see tools/backend/household-integration.sh"))
func aMemberHearsAWalkChangeAndAnOutsiderDoesNot() async throws {
    let config = BackendConfig(baseURL: try #require(Local.url), anonKey: try #require(Local.anonKey))
    let anneClient = config.makeClient(storage: MemoryAuthStorage())
    let brunoClient = config.makeClient(storage: MemoryAuthStorage())
    let drissClient = config.makeClient(storage: MemoryAuthStorage())
    for client in [anneClient, brunoClient, drissClient] {
        _ = try await client.auth.signUp(email: "\(UUID().uuidString.lowercased())@trufflo.test", password: UUID().uuidString)
    }
    let anne = SupabaseRemote(client: anneClient)
    let household = UUID()
    try await anne.createHousehold(id: household, name: "Maison")
    let token = try await anne.createInvite(householdID: household, role: .reader)
    _ = try await SupabaseRemote(client: brunoClient).acceptInvite(token: token)

    final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func ring() { lock.withLock { value = true } }
        var rang: Bool { lock.withLock { value } }
    }
    func listen(_ client: SupabaseClient, into heard: Heard) async throws -> (RealtimeChannelV2, Task<Void, Never>) {
        let channel = client.channel("t-\(UUID().uuidString.lowercased())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "walks",
                                             filter: .eq("household_id", value: household))
        try await channel.subscribeWithError()
        let task = Task { for await _ in changes { heard.ring() } }
        return (channel, task)
    }
    let brunoHeard = Heard(), drissHeard = Heard()
    let (brunoChannel, brunoTask) = try await listen(brunoClient, into: brunoHeard)
    let (drissChannel, drissTask) = try await listen(drissClient, into: drissHeard)

    // On a cold server the first subscription creates Realtime's replication
    // slot, and a change written meanwhile rings nobody. The app only loses a
    // delay (the next foreground sync pulls it); the test writes again until
    // the member hears one, five tries at most.
    let walkID = UUID()
    for attempt in 1...5 where !brunoHeard.rang {
        try await anne.upsertWalk(WalkSummaryDTO(
            id: walkID, householdID: household, source: "manual", quality: "manual",
            startedAt: Date().addingTimeInterval(-1800), endedAt: Date(), confirmedSeconds: Double(1800 + attempt),
            recordedPathMeters: nil, correctedAt: nil))
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !brunoHeard.rang { try await Task.sleep(for: .milliseconds(200)) }
    }
    // Give a leaking event the same chance to reach the outsider.
    try await Task.sleep(for: .seconds(2))
    brunoTask.cancel()
    drissTask.cancel()
    await brunoClient.removeChannel(brunoChannel)
    await drissClient.removeChannel(drissChannel)

    #expect(brunoHeard.rang, "un membre est prévenu d'un changement de balade du foyer")
    #expect(!drissHeard.rang, "un étranger abonné au même filtre n'entend rien")
}

/// B-AC-08, B-AC-09 and the removal, against the real row level security and
/// the keep-an-owner trigger rather than the fake's copy of them.
@MainActor
@Test(.enabled(if: Local.enabled, "needs a local Supabase, see tools/backend/household-integration.sh"))
func ownersManageMembersOverRealHTTP() async throws {
    let config = BackendConfig(baseURL: try #require(Local.url), anonKey: try #require(Local.anonKey))
    let anneRemote = try await account(config)
    let brunoRemote = try await account(config)
    let anneStore = try PersistenceFactory.make(inMemory: true)
    let anneSync = HouseholdSync(context: anneStore.mainContext, remote: anneRemote)
    let brunoStore = try PersistenceFactory.make(inMemory: true)
    let bruno = JournalRepository(context: brunoStore.mainContext)
    let brunoSync = HouseholdSync(context: brunoStore.mainContext, remote: brunoRemote)

    try await anneSync.createHousehold(name: "Maison", displayName: "Anne")
    let household = try #require(anneSync.household()?.id)
    let anneID = try await anneRemote.currentUserID()
    let brunoID = try await brunoRemote.currentUserID()
    let (joined, _) = try await brunoSync.acceptInvite(token: try await anneSync.createInvite(role: .contributor))
    try await brunoSync.completeJoin(joined, displayName: "Bruno", links: [:])

    // A contributor cannot change roles: the server refuses or ignores it.
    try? await brunoRemote.setRole(.owner, userID: brunoID, householdID: household)
    #expect(try await anneRemote.members(householdID: household).first { $0.userID == brunoID }?.role == .contributor)

    // The only owner can be neither demoted nor removed (trigger keep_an_owner).
    await #expect(throws: (any Error).self) { try await anneRemote.setRole(.reader, userID: anneID, householdID: household) }
    await #expect(throws: (any Error).self) { try await anneRemote.leave(householdID: household, userID: anneID) }

    // Demoted to reader, Bruno's walks are refused by the server.
    try await anneSync.setRole(.reader, of: brunoID)
    try await brunoSync.sync()
    #expect(brunoSync.household()?.myRole == .reader)
    let pixel = try bruno.addDog(try DogInput(name: "Pixel", breedKind: "unknown"))
    let walk = try bruno.addManualWalk(try ManualWalkInput(dogIDs: [pixel.id], durationSeconds: 1200, note: ""),
                                       endedAt: Date().addingTimeInterval(-600))
    let summary = WalkSummaryDTO(id: walk.id, householdID: household, source: "manual", quality: "declared",
                                 startedAt: walk.startedAt, endedAt: try #require(walk.endedAt),
                                 confirmedSeconds: 1200, recordedPathMeters: nil, correctedAt: nil)
    await #expect(throws: (any Error).self) { try await brunoRemote.upsertWalk(summary) }

    // Removed, Bruno's next sync finds nothing and forgets the household.
    try await anneSync.remove(memberID: brunoID)
    #expect(try await brunoSync.sync().revoked)
    #expect(brunoSync.household() == nil)

    // Alone, Anne deletes the household; the server no longer has it.
    try await anneSync.deleteHousehold()
    #expect(try await anneRemote.household(id: household) == nil)
}
