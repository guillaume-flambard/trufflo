import Foundation
import Testing
@testable import trufflo

// Session, Apple nonce and request shapes (chantier 3, AC-12, AC-13).

private final class MemoryStore: SessionStoring, @unchecked Sendable {
    var session: AuthSession?
    init(_ session: AuthSession?) { self.session = session }
    func load() -> AuthSession? { session }
    func save(_ session: AuthSession) { self.session = session }
    func clear() { session = nil }
}

private final class ScriptedAuth: AuthEndpoint, @unchecked Sendable {
    var refreshResult: Result<AuthSession, RemoteError>
    var refreshCalls = 0
    init(_ result: Result<AuthSession, RemoteError>) { refreshResult = result }
    func exchange(appleIDToken: String, rawNonce: String) async throws -> AuthSession { throw RemoteError.offline }
    func refresh(_ refreshToken: String) async throws -> AuthSession {
        refreshCalls += 1
        return try refreshResult.get()
    }
    func logout(accessToken: String) async throws {}
}

/// Records every request and answers with a fixed status and body.
private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var answers: [(Int, String)]
    init(_ answers: [(Int, String)]) { self.answers = answers }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = answers.isEmpty ? (200, "[]") : answers.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private let t0 = Date(timeIntervalSince1970: 2_000_000)
private func session(expiresIn seconds: TimeInterval, token: String = "old") -> AuthSession {
    AuthSession(accessToken: token, refreshToken: "r-\(token)", expiresAt: t0.addingTimeInterval(seconds),
                userID: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
}

@Test func theNonceAppleSeesIsTheSha256OfTheNonceGoTrueSees() {
    let raw = AppleNonce.make()
    #expect(raw.count == 64)
    #expect(AppleNonce.make() != raw)
    // Known vector: SHA-256("abc").
    #expect(AppleNonce.hashed("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func aSessionAboutToExpireIsRefreshedFirst() async throws {
    let store = MemoryStore(session(expiresIn: 30))
    let auth = ScriptedAuth(.success(session(expiresIn: 3600, token: "new")))
    let manager = SessionManager(store: store, auth: auth, now: { t0 })

    #expect(try await manager.validSession().accessToken == "new")
    #expect(store.session?.accessToken == "new")
    #expect(try await manager.validSession().accessToken == "new")
    #expect(auth.refreshCalls == 1, "un jeton encore valide n'est pas rafraîchi")
}

@Test func aRefusedRefreshEndsTheSessionButAnOfflineOneKeepsIt() async throws {
    let store = MemoryStore(session(expiresIn: 10))
    let offline = SessionManager(store: store, auth: ScriptedAuth(.failure(.offline)), now: { t0 })
    await #expect(throws: RemoteError.offline) { try await offline.validSession() }
    #expect(store.session != nil, "hors ligne, la session est gardée")

    let refused = SessionManager(store: store, auth: ScriptedAuth(.failure(.rejected("invalid_grant"))), now: { t0 })
    await #expect(throws: RemoteError.signedOut) { try await refused.validSession() }
    #expect(store.session == nil, "refusée, la session est effacée")
}

@Test func theIdTokenExchangeSendsTheRawNonceToGoTrue() async throws {
    let transport = RecordingTransport([(200, #"{"access_token":"a","refresh_token":"r","expires_in":3600,"token_type":"bearer","user":{"id":"00000000-0000-0000-0000-00000000000a"}}"#)])
    let auth = GoTrueAuth(config: BackendConfig(baseURL: URL(string: "https://api.test")!, anonKey: "anon"), transport: transport)
    let result = try await auth.exchange(appleIDToken: "apple.jwt", rawNonce: "raw-nonce")

    let request = try #require(transport.requests.first)
    #expect(request.url?.absoluteString == "https://api.test/auth/v1/token?grant_type=id_token")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
    let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
    #expect(body == ["provider": "apple", "id_token": "apple.jwt", "nonce": "raw-nonce"])
    #expect(result.userID == UUID(uuidString: "00000000-0000-0000-0000-00000000000A"))
}

@Test func writesAskForNoRowBackAndUpsertsMergeDuplicates() async throws {
    let transport = RecordingTransport([(201, ""), (201, "")])
    let manager = SessionManager(store: MemoryStore(session(expiresIn: 3600)), auth: ScriptedAuth(.failure(.offline)), now: { t0 })
    let remote = SupabaseRemote(config: BackendConfig(baseURL: URL(string: "https://api.test")!, anonKey: "anon"),
                                sessions: manager, transport: transport)
    try await remote.createHousehold(id: UUID(), name: "Maison")
    try await remote.upsertWalk(WalkSummaryDTO(id: UUID(), householdID: UUID(), source: "manual", quality: "manual",
                                               startedAt: t0, endedAt: t0, confirmedSeconds: 60,
                                               recordedPathMeters: nil, correctedAt: nil))

    #expect(transport.requests[0].value(forHTTPHeaderField: "Prefer") == "return=minimal")
    #expect(transport.requests[1].value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates,return=minimal")
    #expect(transport.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer old")
    let walkJSON = String(decoding: try #require(transport.requests[1].httpBody), as: UTF8.self)
    #expect(walkJSON.contains(#""recorded_path_meters":null"#), "une distance absente part en null explicite")
}

@Test func aRefusedTokenIsRefreshedOnceThenTheCallIsRetried() async throws {
    let transport = RecordingTransport([(401, #"{"message":"JWT expired"}"#), (200, "[]")])
    let auth = ScriptedAuth(.success(session(expiresIn: 3600, token: "new")))
    let manager = SessionManager(store: MemoryStore(session(expiresIn: 3600)), auth: auth, now: { t0 })
    let remote = SupabaseRemote(config: BackendConfig(baseURL: URL(string: "https://api.test")!, anonKey: "anon"),
                                sessions: manager, transport: transport)

    let household = try await remote.household(id: UUID())
    #expect(household == nil)
    #expect(auth.refreshCalls == 1)
    #expect(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer old", "Bearer new"])
}

@Test func errorsAreTheOnesThePersonCanActOn() {
    func status(_ code: Int, _ body: String = "{}") -> RemoteError? {
        do {
            try HTTPStatus.check(Data(body.utf8), HTTPURLResponse(url: URL(string: "https://a.test")!, statusCode: code, httpVersion: nil, headerFields: nil)!)
            return nil
        } catch { return error as? RemoteError }
    }
    #expect(status(204) == nil)
    #expect(status(401) == .signedOut)
    #expect(status(403, #"{"message":"new row violates row-level security policy"}"#) == .forbidden("new row violates row-level security policy"))
    #expect(status(400, #"{"message":"a household keeps at least one owner"}"#) == .rejected("a household keeps at least one owner"))
    #expect(status(503) == .server(503))
}

@Test func aChangedSinceFilterSurvivesTheQueryString() async throws {
    let transport = RecordingTransport([(200, "[]")])
    let manager = SessionManager(store: MemoryStore(session(expiresIn: 3600)), auth: ScriptedAuth(.failure(.offline)), now: { t0 })
    let remote = SupabaseRemote(config: BackendConfig(baseURL: URL(string: "https://api.test")!, anonKey: "anon"),
                                sessions: manager, transport: transport)
    _ = try await remote.walks(householdID: UUID(), changedSince: Date(timeIntervalSince1970: 1_791_307_338.705))
    let url = try #require(transport.requests.first?.url?.absoluteString)
    #expect(url.contains("updated_at=gt.2026-10-06T17:22:18.705Z"), "\(url)")
    #expect(url.contains("walk_dogs(dog_id,dog_name_snapshot)"))
}
