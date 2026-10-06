import Foundation

/// What leaving the household means for this person (docs/specs/B-foyer-utile.md,
/// B-REQ-05). The server keeps at least one owner, so the screen says so
/// before the person tries, instead of showing a refusal afterwards.
public enum MembershipExit: Equatable, Sendable {
    /// An ordinary member, or one owner among several: leaving is allowed.
    case leave
    /// The only owner, with other members: name another owner first.
    case nameAnotherOwnerFirst
    /// The only member left: leaving would orphan the household, so the way
    /// out is to delete it.
    case deleteHousehold

    public init(myRole: HouseholdRole, roles: [HouseholdRole]) {
        let owners = roles.filter { $0 == .owner }.count
        if myRole != .owner || owners > 1 {
            self = .leave
        } else if roles.count > 1 {
            self = .nameAnotherOwnerFirst
        } else {
            self = .deleteHousehold
        }
    }
}
