import Foundation
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

private final class MemoryStore: SessionStoring, @unchecked Sendable {
    var session: AuthSession?
    func load() -> AuthSession? { session }
    func save(_ session: AuthSession) { self.session = session }
    func clear() { session = nil }
}

/// Signs up a fresh local account and returns the production remote for it.
private func account(_ config: BackendConfig) async throws -> SupabaseRemote {
    struct Response: Decodable {
        struct User: Decodable { var id: UUID }
        var access_token: String; var refresh_token: String; var expires_in: Double; var user: User
    }
    var request = URLRequest(url: config.baseURL.appending(path: "auth/v1/signup"))
    request.httpMethod = "POST"
    request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["email": "\(UUID().uuidString.lowercased())@trufflo.test",
                                                 "password": UUID().uuidString])
    let (data, response) = try await URLSessionTransport().send(request)
    try HTTPStatus.check(data, response)
    let body = try JSONDecoder().decode(Response.self, from: data)
    let store = MemoryStore()
    store.save(AuthSession(accessToken: body.access_token, refreshToken: body.refresh_token,
                           expiresAt: Date().addingTimeInterval(body.expires_in), userID: body.user.id))
    let transport = URLSessionTransport()
    let sessions = SessionManager(store: store, auth: GoTrueAuth(config: config, transport: transport))
    return SupabaseRemote(config: config, sessions: sessions, transport: transport)
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
