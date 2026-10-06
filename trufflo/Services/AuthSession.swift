import CryptoKit
import Foundation
import Security

/// A signed-in session with the household server (GoTrue).
struct AuthSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
}

/// The few HTTP exchanges the app has with GoTrue. Request shapes follow
/// supabase/auth `internal/api/token_oidc.go` (IdTokenGrantParams) and its
/// README (`POST /token?grant_type=refresh_token`, `POST /logout`).
protocol AuthEndpoint: Sendable {
    func exchange(appleIDToken: String, rawNonce: String) async throws -> AuthSession
    func refresh(_ refreshToken: String) async throws -> AuthSession
    func logout(accessToken: String) async throws
}

protocol SessionStoring: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

/// Holds the session and hands out an access token that is valid for at
/// least another minute, refreshing it first when needed (spec S16).
actor SessionManager {
    private let store: any SessionStoring
    private let auth: any AuthEndpoint
    private let now: @Sendable () -> Date
    private var refreshing: Task<AuthSession, Error>?

    static let refreshMargin: TimeInterval = 60

    init(store: any SessionStoring, auth: any AuthEndpoint, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.auth = auth
        self.now = now
    }

    var current: AuthSession? { store.load() }

    func signIn(appleIDToken: String, rawNonce: String) async throws -> AuthSession {
        let session = try await auth.exchange(appleIDToken: appleIDToken, rawNonce: rawNonce)
        store.save(session)
        return session
    }

    func signOut() async {
        if let session = store.load() { try? await auth.logout(accessToken: session.accessToken) }
        store.clear()
    }

    /// Forgets the session without telling the server (global erasure, offline).
    func forget() { store.clear() }

    func validSession() async throws -> AuthSession {
        guard let session = store.load() else { throw RemoteError.signedOut }
        if session.expiresAt.timeIntervalSince(now()) > Self.refreshMargin { return session }
        return try await forceRefresh()
    }

    /// One refresh at a time: concurrent callers wait for the same one. A
    /// refused refresh token ends the session; a network failure keeps it.
    func forceRefresh() async throws -> AuthSession {
        if let refreshing { return try await refreshing.value }
        guard let session = store.load() else { throw RemoteError.signedOut }
        let task = Task { try await auth.refresh(session.refreshToken) }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            store.save(fresh)
            return fresh
        } catch RemoteError.offline {
            throw RemoteError.offline
        } catch {
            store.clear()
            throw RemoteError.signedOut
        }
    }
}

/// The session lives in the keychain, readable only on this device once it
/// has been unlocked once (R-38). Never in UserDefaults, never logged.
struct KeychainSessionStore: SessionStoring {
    let service: String
    private let account = "household-session"

    init(service: String = "dev.memolabs.trufflo.household") { self.service = service }

    func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let update = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clear() { SecItemDelete(baseQuery as CFDictionary) }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

/// Sign in with Apple, native flow. Apple receives the SHA-256 of a random
/// nonce; GoTrue receives the nonce itself and checks that its hash is the
/// one inside Apple's identity token (token_oidc.go, "Nonces mismatch").
enum AppleNonce {
    static func make(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "no secure random bytes")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Lowercase hex SHA-256, the form GoTrue compares against.
    static func hashed(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
