import CryptoKit
import Foundation
import Security
import Supabase

/// Where the Supabase SDK keeps the session: the keychain, readable only on
/// this device once it has been unlocked once (R-38). The SDK's own
/// `KeychainLocalStorage` uses `AfterFirstUnlock`, which lets the session
/// travel with an encrypted backup to another device; this one does not.
struct DeviceOnlyKeychainStorage: AuthLocalStorage {
    let service: String

    init(service: String = "dev.memolabs.trufflo.household") { self.service = service }

    func store(key: String, value: Data) throws {
        let update = [kSecValueData as String: value]
        let status = SecItemUpdate(query(key) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            add[kSecValueData as String] = value
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainFailure(status: added) }
        } else if status != errSecSuccess {
            throw KeychainFailure(status: status)
        }
    }

    func retrieve(key: String) throws -> Data? {
        var read = query(key)
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
        return item as? Data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainFailure(status: status) }
    }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    struct KeychainFailure: Error { let status: OSStatus }
}

/// A session kept in memory only: UI tests and the integration test, which
/// must never touch the keychain of the simulator.
final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

/// Sign in with Apple, native flow. Apple receives the SHA-256 of a random
/// nonce; GoTrue receives the nonce itself and checks that its hash is the
/// one inside Apple's identity token (supabase/auth token_oidc.go,
/// "Nonces mismatch").
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
