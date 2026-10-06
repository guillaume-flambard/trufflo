import Foundation
import Observation
import SwiftData

/// The screen-facing side of the shared household: session, current action,
/// last error. The household itself is read by the views with `@Query`, so
/// what is on screen always comes from the store, never from a copy here.
@MainActor
@Observable
final class HouseholdModel {
    private(set) var isSignedIn = false
    private(set) var isBusy = false
    /// The name Apple gave on the first sign-in, offered as the display name.
    private(set) var suggestedName = ""
    var errorMessage: String?

    /// False in UI tests: no network, no keychain, the screen says so.
    let isAvailable: Bool
    private let container: ModelContainer
    private let sessions: SessionManager?
    private let remote: (any HouseholdRemote)?

    init(container: ModelContainer, sessions: SessionManager?, remote: (any HouseholdRemote)?) {
        self.container = container
        self.sessions = sessions
        self.remote = remote
        isAvailable = remote != nil
    }

    static func production(container: ModelContainer) -> HouseholdModel {
        let config = BackendConfig.production
        let transport = URLSessionTransport()
        let sessions = SessionManager(store: KeychainSessionStore(),
                                      auth: GoTrueAuth(config: config, transport: transport))
        return HouseholdModel(container: container, sessions: sessions,
                              remote: SupabaseRemote(config: config, sessions: sessions, transport: transport))
    }

    static func unavailable(container: ModelContainer) -> HouseholdModel {
        HouseholdModel(container: container, sessions: nil, remote: nil)
    }

    private var sync: HouseholdSync? {
        remote.map { HouseholdSync(context: container.mainContext, remote: $0) }
    }

    // MARK: - Session

    func refreshSessionState() async {
        isSignedIn = await sessions?.current != nil
    }

    func signIn(appleIDToken: String, rawNonce: String, givenName: String?) async {
        guard let sessions else { return }
        await run {
            _ = try await sessions.signIn(appleIDToken: appleIDToken, rawNonce: rawNonce)
            if let givenName, !givenName.isEmpty { suggestedName = givenName }
            isSignedIn = true
        }
    }

    /// Signing out also forgets what was received from the household: without
    /// a session this iPhone can no longer tell whether it may keep it.
    func signOut() async {
        await sessions?.signOut()
        try? sync?.purge()
        isSignedIn = false
    }

    /// Global erasure (spec S12): the session goes with the journal.
    func forgetSession() async {
        await sessions?.forget()
        isSignedIn = false
    }

    // MARK: - Household

    func create(name: String, displayName: String) async {
        guard let sync else { return }
        await run { try await sync.createHousehold(name: name, displayName: displayName) }
    }

    func accept(code: String) async -> (household: HouseholdDTO, dogs: [RemoteDogDTO])? {
        guard let sync else { return nil }
        var result: (HouseholdDTO, [RemoteDogDTO])?
        await run { result = try await sync.acceptInvite(token: code.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return result
    }

    func householdToResume() async -> HouseholdDTO? {
        guard let sync, isSignedIn else { return nil }
        return try? await sync.householdToResume()
    }

    func resume(_ household: HouseholdDTO) async -> (household: HouseholdDTO, dogs: [RemoteDogDTO])? {
        guard let sync else { return nil }
        var result: (HouseholdDTO, [RemoteDogDTO])?
        await run { result = try await sync.resume(household) }
        return result
    }

    func completeJoin(_ household: HouseholdDTO, displayName: String, links: [UUID: UUID?]) async {
        guard let sync else { return }
        await run { try await sync.completeJoin(household, displayName: displayName, links: links) }
    }

    func invite(role: HouseholdRole) async -> String? {
        guard let sync else { return nil }
        var token: String?
        await run { token = try await sync.createInvite(role: role) }
        return token
    }

    func leave() async {
        guard let sync else { return }
        await run { try await sync.leave() }
    }

    /// Quiet when there is nothing to do: no household, no session, already busy.
    func syncNow() async {
        guard let sync, sync.household() != nil, isSignedIn, !isBusy else { return }
        await run { try await sync.sync() }
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch let error as RemoteError {
            if error == .signedOut { isSignedIn = false }
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "L'opération n'a pas abouti. Rien n'a été modifié sur cet iPhone."
        }
    }

    static func message(for error: RemoteError) -> String {
        switch error {
        case .rejected(let detail) where detail.contains("invite not valid"):
            "Ce code n'est pas valable : il a déjà servi, il a expiré ou il a été mal recopié."
        case .rejected(let detail) where detail.contains("at least one owner"):
            "Vous êtes le dernier responsable : le foyer ne peut pas rester sans responsable."
        default:
            error.message
        }
    }
}
