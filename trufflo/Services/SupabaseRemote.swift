import Foundation
import Supabase

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

    /// The official client, with the app's date format on the wire and the
    /// session in the given storage.
    func makeClient(storage: any AuthLocalStorage) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: baseURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: HouseholdCoding.encoder(), decoder: HouseholdCoding.decoder()),
                auth: .init(storage: storage, emitLocalSessionAsInitialSession: true)))
    }
}

/// The household server through the official Supabase SDK (ADR 0008).
///
/// Every write asks for no row back (`returning: .minimal`). The SDK's
/// default for `upsert`, `update` and `delete` is `.representation`, and a
/// household creation cannot read its own row in the same statement (ADR
/// 0007, the RETURNING trap).
struct SupabaseRemote: HouseholdRemote {
    let client: SupabaseClient

    func currentUserID() async throws -> UUID {
        try await mapped { try await client.auth.session.user.id }
    }

    func createHousehold(id: UUID, name: String) async throws {
        struct Row: Encodable { var id: UUID; var name: String }
        try await mapped {
            try await client.from("households").insert(Row(id: id, name: name), returning: .minimal).execute()
        }
    }

    func household(id: UUID) async throws -> HouseholdDTO? {
        try await mapped {
            let rows: [HouseholdDTO] = try await client.from("households").select("id,name")
                .eq("id", value: id).execute().value
            return rows.first
        }
    }

    func myHouseholds() async throws -> [HouseholdDTO] {
        // Row level security returns only the households this person belongs to.
        try await mapped {
            try await client.from("households").select("id,name").order("created_at").execute().value
        }
    }

    func members(householdID: UUID) async throws -> [MemberDTO] {
        struct Member: Decodable { var user_id: UUID; var role: HouseholdRole }
        struct Profile: Decodable { var user_id: UUID; var display_name: String }
        return try await mapped {
            let members: [Member] = try await client.from("household_members").select("user_id,role")
                .eq("household_id", value: householdID).execute().value
            let profiles: [Profile] = try await client.from("member_profiles").select("user_id,display_name")
                .eq("household_id", value: householdID).execute().value
            let names = Dictionary(profiles.map { ($0.user_id, $0.display_name) }, uniquingKeysWith: { a, _ in a })
            return members.map { MemberDTO(userID: $0.user_id, role: $0.role, displayName: names[$0.user_id]) }
        }
    }

    func setDisplayName(_ name: String, householdID: UUID, userID: UUID) async throws {
        struct Row: Encodable { var household_id: UUID; var user_id: UUID; var display_name: String }
        try await mapped {
            try await client.from("member_profiles")
                .upsert(Row(household_id: householdID, user_id: userID, display_name: name), returning: .minimal)
                .execute()
        }
    }

    func createInvite(householdID: UUID, role: HouseholdRole) async throws -> String {
        // An owner may read invites, so this insert can return its token.
        struct Row: Encodable { var household_id: UUID; var role: HouseholdRole }
        struct Created: Decodable { var token: String }
        return try await mapped {
            let created: [Created] = try await client.from("household_invites")
                .insert(Row(household_id: householdID, role: role), returning: .representation)
                .select("token").execute().value
            guard let token = created.first?.token else { throw RemoteError.rejected("invite") }
            return token
        }
    }

    func acceptInvite(token: String) async throws -> UUID {
        struct Args: Encodable { var invite_token: String }
        return try await mapped {
            try await client.rpc("accept_household_invite", params: Args(invite_token: token)).execute().value
        }
    }

    func leave(householdID: UUID, userID: UUID) async throws {
        try await mapped {
            try await client.from("household_members").delete(returning: .minimal)
                .eq("household_id", value: householdID).eq("user_id", value: userID).execute()
        }
    }

    func setRole(_ role: HouseholdRole, userID: UUID, householdID: UUID) async throws {
        try await mapped {
            try await client.from("household_members").update(["role": role.rawValue], returning: .minimal)
                .eq("household_id", value: householdID).eq("user_id", value: userID).execute()
        }
    }

    func deleteHousehold(id: UUID) async throws {
        try await mapped {
            try await client.from("households").delete(returning: .minimal).eq("id", value: id).execute()
        }
    }

    func dogs(householdID: UUID) async throws -> [RemoteDogDTO] {
        try await mapped {
            try await client.from("dogs").select("id,name,breed_kind,breed_label,deleted_at")
                .eq("household_id", value: householdID).execute().value
        }
    }

    func upsertDog(_ dog: DogDTO) async throws {
        try await mapped { try await client.from("dogs").upsert(dog, returning: .minimal).execute() }
    }

    func tombstoneDog(id: UUID, at date: Date) async throws {
        try await tombstone("dogs", id: id, at: date)
    }

    func upsertWalk(_ walk: WalkSummaryDTO) async throws {
        try await mapped { try await client.from("walks").upsert(walk, returning: .minimal).execute() }
    }

    func replaceParticipants(walkID: UUID, with dogs: [WalkDogDTO]) async throws {
        try await mapped {
            try await client.from("walk_dogs").delete(returning: .minimal).eq("walk_id", value: walkID).execute()
            guard !dogs.isEmpty else { return }
            try await client.from("walk_dogs").insert(dogs, returning: .minimal).execute()
        }
    }

    func tombstoneWalk(id: UUID, at date: Date) async throws {
        try await tombstone("walks", id: id, at: date)
    }

    func walks(householdID: UUID, changedSince since: Date?) async throws -> [RemoteWalkDTO] {
        try await mapped {
            var query = client.from("walks")
                .select("id,author_id,revision,source,quality,started_at,ended_at,confirmed_seconds,"
                        + "recorded_path_meters,corrected_at,updated_at,deleted_at,walk_dogs(dog_id,dog_name_snapshot)")
                .eq("household_id", value: householdID)
            if let since { query = query.gt("updated_at", value: HouseholdCoding.format(since)) }
            return try await query.order("updated_at").execute().value
        }
    }

    private func tombstone(_ table: String, id: UUID, at date: Date) async throws {
        struct Patch: Encodable { var deleted_at: Date }
        try await mapped {
            try await client.from(table).update(Patch(deleted_at: date), returning: .minimal)
                .eq("id", value: id).execute()
        }
    }

    /// Every SDK failure becomes one the person can act on (spec S15).
    @discardableResult
    private func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as RemoteError {
            throw error
        } catch {
            throw RemoteError(error)
        }
    }
}

extension RemoteError {
    /// PostgREST reports SQLSTATE codes, not HTTP statuses: 42501 is a row
    /// level security refusal, PGRST30x a refused or expired token. A bare
    /// HTTP error is a server failure; a URL error means no network.
    init(_ error: any Error) {
        switch error {
        case let error as PostgrestError:
            switch error.code {
            case "42501": self = .forbidden(error.message)
            case let code? where code.hasPrefix("PGRST30"): self = .signedOut
            default: self = .rejected(error.message)
            }
        case let error as AuthError:
            switch error {
            case .sessionMissing: self = .signedOut
            case .api(let message, _, _, let response):
                self = response.statusCode >= 500 ? .server(response.statusCode)
                    : response.statusCode == 401 || response.statusCode == 403 ? .signedOut
                    : .rejected(message)
            default: self = .signedOut
            }
        case let error as HTTPError:
            let status = error.response.statusCode
            self = status == 401 ? .signedOut : status == 403 ? .forbidden("\(status)") : status >= 500 ? .server(status) : .rejected("\(status)")
        case is URLError:
            self = .offline
        default:
            self = .rejected(String(describing: error))
        }
    }
}
