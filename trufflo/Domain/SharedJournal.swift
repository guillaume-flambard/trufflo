import Foundation

/// Two people who both recorded the same outing produce two walks. They are
/// flagged, never merged (DATA-CONTRACTS §6, spec S14): only the people know
/// whether it was one outing or two.
public enum PossibleDuplicate {
    public struct Span: Sendable {
        public var start: Date
        public var end: Date
        /// Household dog ids.
        public var dogs: Set<UUID>

        public init(start: Date, end: Date, dogs: Set<UUID>) {
            self.start = start
            self.end = end
            self.dogs = dogs
        }
    }

    /// Same dog, overlapping times.
    public static func overlaps(_ a: Span, _ b: Span) -> Bool {
        a.start < b.end && b.start < a.end && !a.dogs.isDisjoint(with: b.dogs)
    }

    /// The ids among `others` that overlap at least one of `mine`.
    public static func flagged(others: [(id: UUID, span: Span)], mine: [Span]) -> Set<UUID> {
        Set(others.filter { other in mine.contains { overlaps($0, other.span) } }.map(\.id))
    }
}
