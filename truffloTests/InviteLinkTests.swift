import Foundation
import Testing
@testable import trufflo

/// B-AC-02, B-AC-04: the invitation link carries the code and nothing else,
/// and a crafted link opens nothing.
@Suite("Invitation link")
struct InviteLinkTests {
    private let code = "0123456789abcdef0123456789abcdef"

    @Test func aCodeMakesALinkThatGivesTheCodeBack() throws {
        let url = try #require(InviteLink.url(for: code))
        #expect(url.absoluteString == "https://trufflo.memolabs.dev/rejoindre/\(code)")
        #expect(InviteLink.code(in: url) == code)
    }

    @Test func aTrailingSlashOrUppercaseStillReadsTheCode() throws {
        #expect(InviteLink.code(in: try #require(URL(string: "https://trufflo.memolabs.dev/rejoindre/\(code)/"))) == code)
        #expect(InviteLink.code(in: try #require(URL(string: "https://trufflo.memolabs.dev/rejoindre/\(code.uppercased())"))) == code)
    }

    @Test(arguments: [
        "https://evil.example/rejoindre/0123456789abcdef0123456789abcdef",
        "http://trufflo.memolabs.dev/rejoindre/0123456789abcdef0123456789abcdef",
        "https://trufflo.memolabs.dev/rejoindre/0123",
        "https://trufflo.memolabs.dev/rejoindre/0123456789abcdef0123456789abcdeg",
        "https://trufflo.memolabs.dev/rejoindre/0123456789abcdef0123456789abcdef?x=1",
        "https://trufflo.memolabs.dev/autre/0123456789abcdef0123456789abcdef",
        "https://trufflo.memolabs.dev/rejoindre/0123456789abcdef0123456789abcdef/plus",
    ])
    func aCraftedLinkGivesNothing(_ text: String) throws {
        #expect(InviteLink.code(in: try #require(URL(string: text))) == nil)
    }

    @Test func noLinkForSomethingThatIsNotACode() {
        #expect(InviteLink.url(for: "pas un code") == nil)
    }
}
