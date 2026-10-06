import Foundation
import Supabase

/// Whether the app shows the Sorties tab against the real server. False until
/// the community tables and functions exist on `trufflo-api` and the pilot's
/// conditions are met (decisions D5 and D6, a published contact, the server
/// tests: docs/specs/C-premiere-sortie.md). In DEBUG, `--community-server`
/// turns it on to test against a local server without changing this value.
enum CommunityBackend {
    static let isOpen = false
}

/// The community walk events over PostgREST (ADR 0010, « Contrat client »).
///
/// The names of tables, views, functions and parameters below are the contract
/// the server is written against: ADR 0010 lists them, and nothing here has
/// been run against a real server yet (it does not exist at the time of
/// writing). The rules themselves (who sees what, the last place) are the
/// server's; this layer only asks and translates what comes back.
///
/// It shares the household's `SupabaseClient`, so there is one account and one
/// session. Every write that returns nothing says so (`returning: .minimal`),
/// as the household layer does (ADR 0007, the RETURNING trap).
struct SupabaseCommunityRemote: CommunityRemote {
    let client: SupabaseClient

    // MARK: Identity and zones

    func currentUserID() async throws -> UUID {
        try await mapped { try await client.auth.session.user.id }
    }

    func zones() async throws -> [CommunityZone] {
        try await mapped {
            try await client.from("community_zones").select("id,name").eq("is_open", value: true).order("name")
                .execute().value
        }
    }

    // MARK: Profile and dogs

    func myProfile() async throws -> CommunityProfileDTO? {
        struct Row: Decodable {
            var user_id: UUID; var display_name: String; var zone_id: String
            var adult_declared_at: Date; var suspended_at: Date?
        }
        return try await mapped {
            let me = try await client.auth.session.user.id
            let rows: [Row] = try await client.from("community_profiles")
                .select("user_id,display_name,zone_id,adult_declared_at,suspended_at")
                .eq("user_id", value: me).execute().value
            guard let row = rows.first else { return nil }
            // A suspended profile is the same as no profile for the screens.
            if row.suspended_at != nil { throw CommunityError.noProfile }
            return CommunityProfileDTO(userID: row.user_id, displayName: row.display_name,
                                       zoneID: row.zone_id, adultDeclaredAt: row.adult_declared_at)
        }
    }

    func saveProfile(displayName: String, zoneID: String, adultDeclared: Bool) async throws {
        struct Params: Encodable { var display_name: String; var zone_id: String; var adult_declared: Bool }
        try await rpc("save_profile", Params(display_name: displayName, zone_id: zoneID, adult_declared: adultDeclared))
    }

    func myDogs() async throws -> [CommunityDogDTO] {
        try await mapped {
            let me = try await client.auth.session.user.id
            return try await client.from("community_dogs").select("id,owner_id,name,breed_label,public_note")
                .eq("owner_id", value: me).is("deleted_at", value: nil).order("name").execute().value
        }
    }

    func saveDog(_ dog: CommunityDogDTO) async throws {
        try await mapped { try await client.from("community_dogs").upsert(dog, returning: .minimal).execute() }
    }

    func deleteDog(id: UUID) async throws {
        struct Patch: Encodable { var deleted_at: Date }
        try await mapped {
            try await client.from("community_dogs").update(Patch(deleted_at: .now), returning: .minimal)
                .eq("id", value: id).execute()
        }
    }

    // MARK: Events

    func events(zoneID: String) async throws -> [WalkEventDTO] {
        try await mapped {
            try await client.from("visible_events").select().eq("zone_id", value: zoneID).order("starts_at")
                .execute().value
        }
    }

    func myEvents() async throws -> [WalkEventDTO] {
        try await mapped { try await client.from("my_events").select().order("starts_at", ascending: false).execute().value }
    }

    func participants(eventID: UUID) async throws -> [EventParticipantDTO] {
        try await rpc("list_participants", EventParams(event_id: eventID))
    }

    func updates(eventID: UUID) async throws -> [EventUpdateDTO] {
        try await rpc("list_event_updates", EventParams(event_id: eventID))
    }

    // MARK: Taking part

    func requestToJoin(eventID: UUID, dogIDs: [UUID]) async throws {
        struct Params: Encodable { var event_id: UUID; var dog_ids: [UUID] }
        try await rpc("request_to_join", Params(event_id: eventID, dog_ids: dogIDs))
    }

    func withdraw(eventID: UUID) async throws {
        try await rpc("withdraw", EventParams(event_id: eventID))
    }

    func declareAttendance(eventID: UUID, attended: Bool) async throws {
        struct Params: Encodable { var event_id: UUID; var attended: Bool }
        try await rpc("declare_attendance", Params(event_id: eventID, attended: attended))
    }

    // MARK: Organizing

    func isOrganizer(zoneID: String) async throws -> Bool {
        struct Row: Decodable { var zone_id: String }
        return try await mapped {
            let me = try await client.auth.session.user.id
            let rows: [Row] = try await client.from("community_organizers").select("zone_id")
                .eq("user_id", value: me).eq("zone_id", value: zoneID).execute().value
            return !rows.isEmpty
        }
    }

    func createEvent(_ draft: WalkEventDraft, zoneID: String) async throws -> UUID {
        struct Params: Encodable {
            var zone_id: String; var starts_at: Date; var duration_minutes: Int; var meeting_point: String
            var rules: String; var human_capacity: Int; var dog_capacity: Int
        }
        return try await rpc("create_event", Params(
            zone_id: zoneID, starts_at: draft.startsAt, duration_minutes: draft.durationMinutes,
            meeting_point: draft.meetingPoint, rules: draft.rules,
            human_capacity: draft.humanCapacity, dog_capacity: draft.dogCapacity))
    }

    func decide(eventID: UUID, userID: UUID, accept: Bool) async throws {
        struct Params: Encodable { var event_id: UUID; var user_id: UUID; var accept: Bool }
        try await rpc("decide_request", Params(event_id: eventID, user_id: userID, accept: accept))
    }

    func updateEvent(eventID: UUID, startsAt: Date, meetingPoint: String) async throws {
        struct Params: Encodable { var event_id: UUID; var starts_at: Date; var meeting_point: String }
        try await rpc("update_event", Params(event_id: eventID, starts_at: startsAt, meeting_point: meetingPoint))
    }

    func cancelEvent(eventID: UUID) async throws {
        try await rpc("cancel_event", EventParams(event_id: eventID))
    }

    // MARK: Moderation

    func report(_ target: ReportTarget, id: UUID, reason: ReportReason, detail: String) async throws {
        struct Params: Encodable { var target_kind: String; var target_id: UUID; var reason: String; var detail: String }
        try await rpc("report", Params(target_kind: target.rawValue, target_id: id, reason: reason.rawValue, detail: detail))
    }

    func block(userID: UUID) async throws { try await rpc("block", UserParams(user_id: userID)) }
    func unblock(userID: UUID) async throws { try await rpc("unblock", UserParams(user_id: userID)) }

    func blockedPeople() async throws -> [BlockedPersonDTO] {
        try await mapped { try await client.from("my_blocks").select("user_id,display_name").order("display_name").execute().value }
    }

    // MARK: Plumbing

    private struct EventParams: Encodable { var event_id: UUID }
    private struct UserParams: Encodable { var user_id: UUID }

    /// A function that returns nothing.
    private func rpc(_ name: String, _ params: some Encodable) async throws {
        try await mapped { try await client.rpc(name, params: params).execute() }
    }

    /// A function that returns a value or a list of rows.
    private func rpc<T: Decodable>(_ name: String, _ params: some Encodable) async throws -> T {
        try await mapped { try await client.rpc(name, params: params).execute().value }
    }

    /// Every failure becomes one the person can act on. The household layer's
    /// translation of the SDK's errors is reused, then mapped to the community's.
    @discardableResult
    private func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as CommunityError {
            throw error
        } catch {
            throw CommunityError(RemoteError(error))
        }
    }
}

extension CommunityError {
    init(_ error: RemoteError) {
        switch error {
        case .signedOut: self = .signedOut
        case .offline: self = .offline
        case .forbidden: self = .notAllowed
        case .rejected(let detail): self.init(serverMessage: detail)
        case .server(let status): self = .network("HTTP \(status)")
        }
    }
}
