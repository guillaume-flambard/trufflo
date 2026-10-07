import Foundation

/// What the journal says about a chien and a period, computed in one place.
///
/// Today, the dog list and the dog's page used to derive these figures each on
/// their own, and the walk count per chien was written three times. Every
/// screen now reads them here, with the time and the calendar given, so the
/// figures are tested without a screen and cannot disagree between screens.
public struct JournalFacts: Sendable {
    /// One balade, reduced to what the facts need.
    public struct Walk: Equatable, Sendable {
        public let id: UUID
        public let startedAt: Date
        public let endedAt: Date?
        public let seconds: TimeInterval
        public let phase: WalkPhase
        public let dogIDs: Set<UUID>

        public init(id: UUID, startedAt: Date, endedAt: Date?, seconds: TimeInterval,
                    phase: WalkPhase, dogIDs: Set<UUID>) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.seconds = seconds
            self.phase = phase
            self.dogIDs = dogIDs
        }

        /// Where the balade sits in time: its end, or its start when no end was
        /// recorded.
        var date: Date { endedAt ?? startedAt }
    }

    private let completed: [Walk]
    private let now: Date
    private let calendar: Calendar

    /// The latest finished balade, by its end.
    public let lastWalkID: UUID?
    /// The balade en cours (moving, paused or interrompue), the most recently
    /// started one if several survived a crash.
    public let liveWalkID: UUID?

    public init(walks: [Walk], now: Date, calendar: Calendar) {
        completed = walks.filter { $0.phase == .completed }
        lastWalkID = completed.max { $0.date < $1.date }?.id
        liveWalkID = walks
            .filter { [.recording, .paused, .interrupted].contains($0.phase) }
            .max { $0.startedAt < $1.startedAt }?.id
        self.now = now
        self.calendar = calendar
    }

    /// Finished balades this chien was on.
    public func walkCount(for dogID: UUID) -> Int {
        walks(of: dogID).count
    }

    /// Time is safe to add up: every balade has a duration, suivie or ajoutée.
    /// Distance is not, so there is no distance total.
    public func totalSeconds(for dogID: UUID) -> TimeInterval {
        walks(of: dogID).map(\.seconds).reduce(0, +)
    }

    /// Finished balades of this chien on the calendar day of `now`: what the
    /// routine line reads ("Aujourd'hui, 2 balades enregistrées").
    public func todayCount(for dogID: UUID) -> Int {
        walks(of: dogID).filter { calendar.isDate($0.date, inSameDayAs: now) }.count
    }

    /// The calendar week of `now`, Monday to Sunday: the one meaning of "cette
    /// semaine" on Today and in the Journal.
    public var week: WeekSummary {
        WeekSummary.make(walks: completed.map { .init(endedAt: $0.date, seconds: $0.seconds) },
                         now: now, calendar: calendar)
    }

    private func walks(of dogID: UUID) -> [Walk] {
        completed.filter { $0.dogIDs.contains(dogID) }
    }
}
