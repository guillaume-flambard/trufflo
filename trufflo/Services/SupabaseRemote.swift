import Foundation

/// Where the household server lives. The anon key is public by design: it
/// only identifies the project, it grants nothing (the `anon` role has no
/// grant on any table, see backend/supabase). No service key ever ships.
struct BackendConfig: Sendable {
    var baseURL: URL
    var anonKey: String

    /// `trufflo-api` on the lab VPS (ADR 0007). The anon JWT expires on
    /// 2031-10-06, five years after the stack's secrets were generated.
    static let production = BackendConfig(
        baseURL: URL(string: "https://trufflo-api.memolabs.dev")!,
        anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzkxMzA3ODIyLCJleHAiOjE5NDg5ODc4MjJ9.bqXc4ETciLxPFu4MfqBgdGpGoilkyDkwoUR_fJdSb-4")
}

/// One HTTP round trip. Production is URLSession; tests record requests.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RemoteError.offline }
            return (data, http)
        } catch is URLError {
            throw RemoteError.offline
        }
    }
}

/// Maps an HTTP answer to the errors the person can act on (spec S15).
/// PostgREST answers 403 for a row level security refusal (SQLSTATE 42501)
/// and 400 for a check violation.
enum HTTPStatus {
    static func check(_ data: Data, _ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw RemoteError.signedOut
        case 403: throw RemoteError.forbidden(message(data))
        case 400..<500: throw RemoteError.rejected(message(data))
        default: throw RemoteError.server(response.statusCode)
        }
    }

    static func message(_ data: Data) -> String {
        struct Body: Decodable { var message: String?; var msg: String?; var error_description: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        return body?.message ?? body?.msg ?? body?.error_description ?? String(decoding: data.prefix(200), as: UTF8.self)
    }
}

/// GoTrue over HTTP.
struct GoTrueAuth: AuthEndpoint {
    let config: BackendConfig
    let transport: any HTTPTransport

    private struct TokenResponse: Decodable {
        struct User: Decodable { var id: UUID }
        var access_token: String
        var refresh_token: String
        var expires_in: Double
        var user: User
    }

    func exchange(appleIDToken: String, rawNonce: String) async throws -> AuthSession {
        try await token(grant: "id_token",
                        body: ["provider": "apple", "id_token": appleIDToken, "nonce": rawNonce])
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        try await token(grant: "refresh_token", body: ["refresh_token": refreshToken])
    }

    func logout(accessToken: String) async throws {
        var request = URLRequest(url: config.baseURL.appending(path: "auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        try HTTPStatus.check(data, response)
    }

    private func token(grant: String, body: [String: String]) async throws -> AuthSession {
        var components = URLComponents(url: config.baseURL.appending(path: "auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grant)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let sentAt = Date()
        let (data, response) = try await transport.send(request)
        try HTTPStatus.check(data, response)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthSession(accessToken: decoded.access_token, refreshToken: decoded.refresh_token,
                           expiresAt: sentAt.addingTimeInterval(decoded.expires_in), userID: decoded.user.id)
    }
}

/// The household server through PostgREST. Every write asks for no row back
/// (`return=minimal`): a creation cannot read its own row in the same
/// statement (ADR 0007, the RETURNING trap).
struct SupabaseRemote: HouseholdRemote {
    let config: BackendConfig
    let sessions: SessionManager
    let transport: any HTTPTransport

    func currentUserID() async throws -> UUID { try await sessions.validSession().userID }

    func createHousehold(id: UUID, name: String) async throws {
        struct Row: Encodable { var id: UUID; var name: String }
        try await write("POST", "households", body: Row(id: id, name: name))
    }

    func household(id: UUID) async throws -> HouseholdDTO? {
        let rows: [HouseholdDTO] = try await read("households", ["id": "eq.\(id.uuidString)", "select": "id,name"])
        return rows.first
    }

    func myHouseholds() async throws -> [HouseholdDTO] {
        // Row level security returns only the households this person belongs to.
        try await read("households", ["select": "id,name", "order": "created_at.asc"])
    }

    func members(householdID: UUID) async throws -> [MemberDTO] {
        struct Member: Decodable { var user_id: UUID; var role: HouseholdRole }
        struct Profile: Decodable { var user_id: UUID; var display_name: String }
        let filter = "eq.\(householdID.uuidString)"
        let members: [Member] = try await read("household_members", ["household_id": filter, "select": "user_id,role"])
        let profiles: [Profile] = try await read("member_profiles", ["household_id": filter, "select": "user_id,display_name"])
        let names = Dictionary(profiles.map { ($0.user_id, $0.display_name) }, uniquingKeysWith: { a, _ in a })
        return members.map { MemberDTO(userID: $0.user_id, role: $0.role, displayName: names[$0.user_id]) }
    }

    func setDisplayName(_ name: String, householdID: UUID, userID: UUID) async throws {
        struct Row: Encodable { var household_id: UUID; var user_id: UUID; var display_name: String }
        try await write("POST", "member_profiles",
                        body: Row(household_id: householdID, user_id: userID, display_name: name), upsert: true)
    }

    func createInvite(householdID: UUID, role: HouseholdRole) async throws -> String {
        // An owner may read invites, so this insert can return its token.
        struct Row: Encodable { var household_id: UUID; var role: HouseholdRole }
        struct Created: Decodable { var token: String }
        let data = try await send("POST", "household_invites", query: ["select": "token"],
                                  body: try encode([Row(household_id: householdID, role: role)]),
                                  prefer: "return=representation")
        guard let token = try HouseholdCoding.decoder().decode([Created].self, from: data).first?.token else {
            throw RemoteError.rejected("invite")
        }
        return token
    }

    func acceptInvite(token: String) async throws -> UUID {
        struct Args: Encodable { var invite_token: String }
        let data = try await send("POST", "rpc/accept_household_invite", query: [:],
                                  body: try encode(Args(invite_token: token)), prefer: nil)
        return try JSONDecoder().decode(UUID.self, from: data)
    }

    func leave(householdID: UUID, userID: UUID) async throws {
        _ = try await send("DELETE", "household_members",
                           query: ["household_id": "eq.\(householdID.uuidString)", "user_id": "eq.\(userID.uuidString)"],
                           body: nil, prefer: "return=minimal")
    }

    func dogs(householdID: UUID) async throws -> [RemoteDogDTO] {
        try await read("dogs", ["household_id": "eq.\(householdID.uuidString)",
                                "select": "id,name,breed_kind,breed_label,deleted_at"])
    }

    func upsertDog(_ dog: DogDTO) async throws {
        try await write("POST", "dogs", body: dog, upsert: true)
    }

    func tombstoneDog(id: UUID, at date: Date) async throws {
        try await tombstone("dogs", id: id, at: date)
    }

    func upsertWalk(_ walk: WalkSummaryDTO) async throws {
        try await write("POST", "walks", body: walk, upsert: true)
    }

    func replaceParticipants(walkID: UUID, with dogs: [WalkDogDTO]) async throws {
        _ = try await send("DELETE", "walk_dogs", query: ["walk_id": "eq.\(walkID.uuidString)"],
                           body: nil, prefer: "return=minimal")
        guard !dogs.isEmpty else { return }
        _ = try await send("POST", "walk_dogs", query: [:], body: try encode(dogs), prefer: "return=minimal")
    }

    func tombstoneWalk(id: UUID, at date: Date) async throws {
        try await tombstone("walks", id: id, at: date)
    }

    func walks(householdID: UUID, changedSince since: Date?) async throws -> [RemoteWalkDTO] {
        var query = [
            "household_id": "eq.\(householdID.uuidString)",
            "select": "id,author_id,revision,source,quality,started_at,ended_at,confirmed_seconds,"
                + "recorded_path_meters,corrected_at,updated_at,deleted_at,walk_dogs(dog_id,dog_name_snapshot)",
            "order": "updated_at.asc",
        ]
        if let since { query["updated_at"] = "gt.\(HouseholdCoding.format(since))" }
        return try await read("walks", query)
    }

    // MARK: - Plumbing

    private func tombstone(_ table: String, id: UUID, at date: Date) async throws {
        struct Patch: Encodable { var deleted_at: Date }
        _ = try await send("PATCH", table, query: ["id": "eq.\(id.uuidString)"],
                           body: try encode(Patch(deleted_at: date)), prefer: "return=minimal")
    }

    private func read<T: Decodable>(_ table: String, _ query: [String: String]) async throws -> [T] {
        let data = try await send("GET", table, query: query, body: nil, prefer: nil)
        return try HouseholdCoding.decoder().decode([T].self, from: data)
    }

    private func write<T: Encodable>(_ method: String, _ table: String, body: T, upsert: Bool = false) async throws {
        _ = try await send(method, table, query: [:], body: try encode(body),
                           prefer: upsert ? "resolution=merge-duplicates,return=minimal" : "return=minimal")
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data { try HouseholdCoding.encoder().encode(value) }

    /// One request, with one retry after a refresh when the token was refused.
    func send(_ method: String, _ path: String, query: [String: String], body: Data?, prefer: String?) async throws -> Data {
        do {
            return try await attempt(method, path, query, body, prefer, session: try await sessions.validSession())
        } catch RemoteError.signedOut {
            return try await attempt(method, path, query, body, prefer, session: try await sessions.forceRefresh())
        }
    }

    private func attempt(_ method: String, _ path: String, _ query: [String: String], _ body: Data?,
                         _ prefer: String?, session: AuthSession) async throws -> Data {
        var components = URLComponents(url: config.baseURL.appending(path: "rest/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            // URLComponents leaves "+" alone, and PostgREST would read it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let (data, response) = try await transport.send(request)
        try HTTPStatus.check(data, response)
        return data
    }
}
