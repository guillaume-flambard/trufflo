import Foundation

/// The invitation as a link (B-REQ-02, ADR 0009):
/// https://trufflo.memolabs.dev/rejoindre/<code>.
///
/// The link only carries the code the server already issues; accepting it
/// still goes through `accept_household_invite`, which checks it is valid,
/// unused and unexpired. A universal link is an entry point anyone can craft,
/// so anything that is not exactly a code is ignored (Apple, "Supporting
/// universal links in your app": validate every parameter).
public enum InviteLink {
    public static let host = "trufflo.memolabs.dev"
    static let pathPrefix = "/rejoindre/"

    public static func url(for code: String) -> URL? {
        guard isCode(code) else { return nil }
        return URL(string: "https://\(host)\(pathPrefix)\(code)")
    }

    /// The code in a link this app should act on, or nil.
    public static func code(in url: URL) -> String? {
        guard url.scheme == "https", url.host() == host,
              url.query() == nil, url.fragment() == nil else { return nil }
        var path = url.path()
        if path.hasSuffix("/") { path.removeLast() }
        guard path.hasPrefix(pathPrefix) else { return nil }
        let code = String(path.dropFirst(pathPrefix.count)).lowercased()
        return isCode(code) ? code : nil
    }

    /// The server's token: 32 hexadecimal characters (`gen_random_uuid()`
    /// without its hyphens, backend/supabase household_sharing).
    static func isCode(_ text: String) -> Bool {
        text.count == 32 && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
