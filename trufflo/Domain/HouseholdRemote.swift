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
    /// Returns the household joined.
    func acceptInvite(token: String) async throws -> UUID
    func leave(householdID: UUID, userID: UUID) async throws

    func dogs(householdID: UUID) async throws -> [RemoteDogDTO]
    func upsertDog(_ dog: DogDTO) async throws
    func tombstoneDog(id: UUID, at date: Date) async throws

    func upsertWalk(_ walk: WalkSummaryDTO) async throws
    func replaceParticipants(walkID: UUID, with dogs: [WalkDogDTO]) async throws
    func tombstoneWalk(id: UUID, at date: Date) async throws
    /// Walks of the household changed after `since` (all of them when nil),
    /// tombstones included.
    func walks(householdID: UUID, changedSince since: Date?) async throws -> [RemoteWalkDTO]
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
