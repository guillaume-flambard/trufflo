import Foundation

/// Everything the app asks of the household server. Production talks to
/// Supabase over HTTPS; tests use an in-memory fake that enforces the same
/// rules, so the sync logic is tested in milliseconds without a network.
public protocol HouseholdRemote: Sendable {
    /// The signed-in person, as the server knows them.
    func currentUserID() async throws -> UUID

    func createHousehold(id: UUID, name: String) async throws
    /// Nil when the server no longer lets this person read the household.
    func household(id: UUID) async throws -> HouseholdDTO?
    /// Every household this person is a member of, as the server sees it:
    /// how a reinstalled or signed-out iPhone finds its household again.
    func myHouseholds() async throws -> [HouseholdDTO]
    func members(householdID: UUID) async throws -> [MemberDTO]
    func setDisplayName(_ name: String, householdID: UUID, userID: UUID) async throws
    func createInvite(householdID: UUID, role: HouseholdRole) async throws -> String
    /// Owners only: invites neither used, revoked nor expired.
    func pendingInvites(householdID: UUID, now: Date) async throws -> [PendingInviteDTO]
    /// Owners only. A revoked invite can no longer be accepted.
    func revokeInvite(id: UUID, at date: Date) async throws
    /// Returns the household joined.
    func acceptInvite(token: String) async throws -> UUID
    /// Removes a membership: the person's own (leaving), or another member's
    /// when the caller is an owner. The server keeps at least one owner.
    func leave(householdID: UUID, userID: UUID) async throws
    /// Owners only. The server refuses to demote the last owner.
    func setRole(_ role: HouseholdRole, userID: UUID, householdID: UUID) async throws
    /// Owners only. Everything of the household goes with it on the server;
    /// each member's own journal stays on their iPhone.
    func deleteHousehold(id: UUID) async throws
    /// Deletes the signed-in account and what the server holds for it. A
    /// household the person alone shares goes with it; the server refuses
    /// while others remain and none of them is an owner.
    func deleteMyAccount() async throws

    func dogs(householdID: UUID) async throws -> [RemoteDogDTO]
    func upsertDog(_ dog: DogDTO) async throws
    func tombstoneDog(id: UUID, at date: Date) async throws

    func upsertWalk(_ walk: WalkSummaryDTO) async throws
    func replaceParticipants(walkID: UUID, with dogs: [WalkDogDTO]) async throws
    func tombstoneWalk(id: UUID, at date: Date) async throws
    /// Walks of the household changed after `since` (all of them when nil),
    /// tombstones included.
    func walks(householdID: UUID, changedSince since: Date?) async throws -> [RemoteWalkDTO]

    /// Writes my live position (one row per member, overwritten).
    func shareLivePosition(_ position: LivePositionDTO) async throws
    /// Deletes my live position.
    func stopLivePosition(householdID: UUID, userID: UUID) async throws
    /// The household's live positions not expired, mine included.
    func livePositions(householdID: UUID) async throws -> [RemoteLivePositionDTO]

    func upsertPlannedWalk(_ plan: PlannedWalkDTO) async throws
    func tombstonePlannedWalk(id: UUID, at date: Date) async throws
    /// The household's planned balades still to come, none deleted.
    func plannedWalks(householdID: UUID, after date: Date) async throws -> [RemotePlannedWalkDTO]
}

/// Failures the person can act on, kept distinct (spec S15).
public enum RemoteError: Error, Equatable, Sendable {
    /// No network, or the server did not answer.
    case offline
    /// The session is missing or refused even after a refresh.
    case signedOut
    /// The server refused this action for this person (RLS, role).
    case forbidden(String)
    /// The request was refused as invalid (a rule of the schema).
    case rejected(String)
    case server(Int)

    public var message: String {
        switch self {
        case .offline: "Pas de connexion au serveur. Rien n'est perdu, la synchronisation reprendra."
        case .signedOut: "Votre session a expiré. Reconnectez-vous pour reprendre la synchronisation."
        case .forbidden: "Le foyer a refusé cette action pour votre rôle."
        case .rejected(let detail): "Le serveur a refusé ces données : \(detail)"
        case .server(let status): "Le serveur a rencontré une erreur (\(status)). Réessayez plus tard."
        }
    }
}
