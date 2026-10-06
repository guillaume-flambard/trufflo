import Foundation
import Observation
import Supabase
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
    /// Set when a sync finds this person is no longer a member: the name of
    /// the household that was forgotten, so the screens can say so once.
    var lostHousehold: String?
    /// A code that arrived through an invitation link (B-REQ-02), waiting for
    /// the household screen to place it in « Rejoindre ».
    var pendingInviteCode: String?

    /// False in UI tests: no network, no keychain, the screen says so.
    let isAvailable: Bool
    private let container: ModelContainer
    private let client: SupabaseClient?
    private let remote: (any HouseholdRemote)?
    private var liveChannel: RealtimeChannelV2?
    private var liveTask: Task<Void, Never>?

    init(container: ModelContainer, client: SupabaseClient?, available: Bool? = nil) {
        self.container = container
        self.client = client
        remote = client.map(SupabaseRemote.init(client:))
        isAvailable = available ?? (client != nil)
    }

    static func production(container: ModelContainer) -> HouseholdModel {
        HouseholdModel(container: container,
                       client: BackendConfig.production.makeClient(storage: DeviceOnlyKeychainStorage()))
    }

    static func unavailable(container: ModelContainer) -> HouseholdModel {
        HouseholdModel(container: container, client: nil)
    }

    #if DEBUG
    /// `--demo-signed-in`: screenshots of the signed-in states without Apple.
    /// Every server action is a no-op; the screens only read the store.
    private(set) var isDemo = false

    static func demoSignedIn(container: ModelContainer) -> HouseholdModel {
        let model = HouseholdModel(container: container, client: nil, available: true)
        model.isSignedIn = true
        model.isDemo = true
        return model
    }
    #endif

    private var sync: HouseholdSync? {
        remote.map { HouseholdSync(context: container.mainContext, remote: $0) }
    }

    // MARK: - Session

    func refreshSessionState() async {
        #if DEBUG
        if isDemo { return }
        #endif
        isSignedIn = client?.auth.currentSession != nil
    }

    func signIn(appleIDToken: String, rawNonce: String, givenName: String?) async {
        guard let client else { return }
        await run {
            _ = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: appleIDToken, nonce: rawNonce))
            if let givenName, !givenName.isEmpty { suggestedName = givenName }
            isSignedIn = true
        }
    }

    /// Signing out also forgets what was received from the household: without
    /// a session this iPhone can no longer tell whether it may keep it.
    func signOut() async {
        await stopLiveUpdates()
        // The SDK removes the local session before it calls the server, so a
        // failed network call still leaves this iPhone signed out.
        try? await client?.auth.signOut(scope: .local)
        try? sync?.purge()
        isSignedIn = false
    }

    /// Global erasure (spec S12): the session goes with the journal.
    func forgetSession() async {
        await stopLiveUpdates()
        try? await client?.auth.signOut(scope: .local)
        isSignedIn = false
    }

    // MARK: - Live updates (Realtime)

    /// While the app is in front, a change to a walk of the household starts a
    /// synchronisation. The event is only a doorbell: what is shown still comes
    /// from the same pull, under the same rules, so a missed event costs a
    /// delay, never a wrong journal.
    func startLiveUpdates() async {
        guard let client, liveChannel == nil, isSignedIn,
              let household = sync?.household() else { return }
        let channel = client.channel("household-\(household.id.uuidString.lowercased())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "walks",
                                             filter: .eq("household_id", value: household.id))
        liveChannel = channel
        liveTask = Task { [weak self] in
            do { try await channel.subscribeWithError() } catch { return }
            for await _ in changes {
                guard let self else { return }
                // Several rows change together on one sync: let them land first.
                try? await Task.sleep(for: .milliseconds(800))
                await self.syncNow()
            }
        }
    }

    func stopLiveUpdates() async {
        liveTask?.cancel()
        liveTask = nil
        if let liveChannel, let client { await client.removeChannel(liveChannel) }
        liveChannel = nil
    }

    // MARK: - Household

    func create(name: String, displayName: String) async {
        guard let sync else { return }
        await run { try await sync.createHousehold(name: name, displayName: displayName) }
        await startLiveUpdates()
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
        await startLiveUpdates()
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
        if sync.household() == nil { await stopLiveUpdates() }
    }

    func setRole(_ role: HouseholdRole, of userID: UUID) async {
        guard let sync else { return }
        await run { try await sync.setRole(role, of: userID) }
    }

    func remove(memberID: UUID) async {
        guard let sync else { return }
        await run { try await sync.remove(memberID: memberID) }
    }

    func deleteHousehold() async {
        guard let sync else { return }
        await run { try await sync.deleteHousehold() }
        if sync.household() == nil { await stopLiveUpdates() }
    }

    /// Quiet when there is nothing to do: no household, no session, already busy.
    func syncNow() async {
        guard let sync, let name = sync.household()?.name, isSignedIn, !isBusy else { return }
        await run {
            if try await sync.sync().revoked { lostHousehold = name }
        }
        // Revoked during this sync: nothing left to listen to.
        if sync.household() == nil { await stopLiveUpdates() }
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            let remoteError = error as? RemoteError ?? RemoteError(error)
            if remoteError == .signedOut { isSignedIn = false }
            errorMessage = Self.message(for: remoteError)
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
