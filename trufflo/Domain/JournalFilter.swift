import Foundation

/// The journal's filter by dog and by period (PRD F05). Pure, so the rule that
/// decides what a filtered journal shows is tested without any screen.
public struct JournalFilter: Equatable, Sendable {
    public enum Period: String, CaseIterable, Sendable {
        case all, lastSevenDays, lastThirtyDays, thisYear

        public var label: String {
            switch self {
            case .all: "Tout"
            case .lastSevenDays: "7 derniers jours"
            case .lastThirtyDays: "30 derniers jours"
            case .thisYear: "Cette année"
            }
        }
    }

    /// Which balades: mine (all, suivies, ajoutées, with photos), or the
    /// foyer's, which are listed under their own chip only.
    public enum Kind: String, CaseIterable, Sendable {
        case all, tracked, added, photos, household

        public var label: String {
            switch self {
            case .all: "Toutes"
            case .tracked: "Avec GPS"
            case .added: "Ajoutées"
            case .photos: "Photos"
            case .household: "Foyer"
            }
        }
    }

    /// Nil means every dog.
    public var dogID: UUID?
    public var period: Period
    public var kind: Kind

    public init(dogID: UUID? = nil, period: Period = .all, kind: Kind = .all) {
        self.dogID = dogID
        self.period = period
        self.kind = kind
    }

    public var isActive: Bool { dogID != nil || period != .all || kind != .all }

    /// Whether a balade of this kind passes the chips of the Journal.
    public func includes(isTracked: Bool, hasPhotos: Bool = false) -> Bool {
        switch kind {
        case .all: true
        case .tracked: isTracked
        case .added: !isTracked
        case .photos: hasPhotos
        case .household: false
        }
    }

    /// Whether a walk that ended at `date`, with these dogs, belongs in the
    /// filtered journal. A walk with several dogs matches each of them.
    public func includes(date: Date, dogIDs: Set<UUID>, now: Date = Date(),
                         calendar: Calendar = .current) -> Bool {
        if let dogID, !dogIDs.contains(dogID) { return false }
        switch period {
        case .all:
            return true
        case .lastSevenDays:
            return date >= now.addingTimeInterval(-7 * 24 * 3600)
        case .lastThirtyDays:
            return date >= now.addingTimeInterval(-30 * 24 * 3600)
        case .thisYear:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
        }
    }
}
