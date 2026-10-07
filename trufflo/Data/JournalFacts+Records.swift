import Foundation

extension JournalFacts {
    /// The facts of the stored journal: each balade with the chiens on it, read
    /// once here rather than in every screen that shows a count.
    init(walks: [WalkRecord], links: [WalkDogRecord], now: Date = .now,
         calendar: Calendar = TruffloLocale.calendar) {
        let dogsByWalk = Dictionary(grouping: links, by: \.walkID).mapValues { Set($0.map(\.dogID)) }
        self.init(walks: walks.map { walk in
            Walk(id: walk.id, startedAt: walk.startedAt, endedAt: walk.endedAt,
                 seconds: walk.confirmedSeconds, phase: walk.phase,
                 dogIDs: dogsByWalk[walk.id] ?? [])
        }, now: now, calendar: calendar)
    }
}
