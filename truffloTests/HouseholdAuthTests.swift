import Foundation
import Supabase
import Testing
@testable import trufflo

// Apple nonce, session storage and error mapping (chantier 3, AC-12, S15).
// Request shapes are the official SDK's; the HTTP journey itself is
// covered by HouseholdIntegrationTests against a local Supabase.

@Test func theNonceAppleSeesIsTheSha256OfTheNonceGoTrueSees() {
    let raw = AppleNonce.make()
    #expect(raw.count == 64)
    #expect(AppleNonce.make() != raw)
    // Known vector: SHA-256("abc").
    #expect(AppleNonce.hashed("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func theSessionStorageKeepsReplacesAndForgets() throws {
    let storage = DeviceOnlyKeychainStorage(service: "dev.memolabs.trufflo.tests.\(UUID().uuidString)")
    defer { try? storage.remove(key: "session") }
    #expect(try storage.retrieve(key: "session") == nil)
    try storage.store(key: "session", value: Data("one".utf8))
    try storage.store(key: "session", value: Data("two".utf8))
    #expect(try storage.retrieve(key: "session") == Data("two".utf8))
    try storage.remove(key: "session")
    #expect(try storage.retrieve(key: "session") == nil)
}

@Test func sdkFailuresBecomeErrorsThePersonCanActOn() {
    #expect(RemoteError(PostgrestError(code: "42501", message: "new row violates row-level security policy"))
            == .forbidden("new row violates row-level security policy"))
    #expect(RemoteError(PostgrestError(code: "PGRST303", message: "JWT expired")) == .signedOut)
    #expect(RemoteError(PostgrestError(code: "23514", message: "a household keeps at least one owner"))
            == .rejected("a household keeps at least one owner"))
    #expect(RemoteError(URLError(.notConnectedToInternet)) == .offline)
    #expect(RemoteError(AuthError.sessionMissing) == .signedOut)
    let response = HTTPURLResponse(url: URL(string: "https://a.test")!, statusCode: 503, httpVersion: nil, headerFields: nil)!
    #expect(RemoteError(HTTPError(data: Data(), response: response)) == .server(503))
}

@MainActor
@Test func theLastOwnerAndABadCodeAreSaidInPlainWords() {
    #expect(HouseholdModel.message(for: .rejected("invite not valid")).contains("Ce code n'est pas valable"))
    #expect(HouseholdModel.message(for: .rejected("a household keeps at least one owner")).contains("dernier responsable"))
}
