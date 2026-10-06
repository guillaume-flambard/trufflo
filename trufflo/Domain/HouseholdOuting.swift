import Foundation

/// Which walk of the other members Today shows (B-REQ-04, decision D2).
///
/// Today's figures stay the person's own. Beside them, one block names the
/// latest outing a member recorded, if it is more recent than the person's
/// own last walk: that is the news. A walk flagged as possibly the same outing
/// as one of the person's is not news, it is already counted on their side.
public enum HouseholdOuting {
    public struct Candidate: Equatable, Sendable {
        public let id: UUID
        public let endedAt: Date
        public let isPossibleDuplicate: Bool

        public init(id: UUID, endedAt: Date, isPossibleDuplicate: Bool) {
            self.id = id
            self.endedAt = endedAt
            self.isPossibleDuplicate = isPossibleDuplicate
        }
    }

    public static func latest(_ candidates: [Candidate], myLastEndedAt: Date?) -> UUID? {
        candidates
            .filter { !$0.isPossibleDuplicate && $0.endedAt > (myLastEndedAt ?? .distantPast) }
            .max { $0.endedAt < $1.endedAt }?
            .id
    }
}
