import Foundation

/// What every screen shows of one balade: the tile of Today, the journal row, the
/// walk page and the bilan.
///
/// Each of the four used to derive this on its own, and they had drifted: the
/// tile took the first chien with a photo, the walk page the first chien still on
/// the iPhone, so the same balade showed a face in one place and none in the
/// other. The rules live here, tested without a screen.
public struct WalkPresentation: Sendable {
    /// A chien named on the balade, with the name it had at the time.
    public struct Participant: Equatable, Sendable {
        public let dogID: UUID
        public let name: String

        public init(dogID: UUID, name: String) {
            self.dogID = dogID
            self.name = name
        }
    }

    /// A chien still on this iPhone, in the order of "Mes chiens".
    public struct Dog: Equatable, Sendable {
        public let id: UUID
        public let photo: Data?

        public init(id: UUID, photo: Data?) {
            self.id = id
            self.photo = photo
        }
    }

    /// The chiens' names, alphabetical.
    public let names: [String]
    /// The face of the balade: the first chien on it, in the order of "Mes
    /// chiens", that has a photo. Nil when none has one: no stand-in face.
    public let leadPhoto: Data?
    /// The name of the chien whose face is shown, for VoiceOver.
    public let leadName: String?
    /// A balade suivie, recorded live; otherwise a balade ajoutée.
    public let isTracked: Bool
    /// Where the balade sits in time: its end, or its start without one.
    public let date: Date
    private let points: [TrackCoordinate]

    public init(isTracked: Bool, startedAt: Date, endedAt: Date?,
                participants: [Participant], dogs: [Dog], points: [TrackCoordinate]) {
        self.isTracked = isTracked
        date = endedAt ?? startedAt
        self.points = points
        names = participants.map(\.name).sorted()
        let onWalk = Set(participants.map(\.dogID))
        let lead = dogs.first { onWalk.contains($0.id) && $0.photo != nil }
        leadPhoto = lead?.photo
        leadName = lead.flatMap { dog in participants.first { $0.dogID == dog.id }?.name }
    }

    /// "Oslo et Pixel", or "Balade" when no chien is left on it.
    public var title: String {
        names.isEmpty ? "Balade" : names.formatted(.list(type: .and).locale(TruffloLocale.french))
    }

    /// The tracé, or nil when there is none to draw: a balade ajoutée, or fewer
    /// than two points. With `maxPoints`, a picture of it: the start and the end
    /// of every segment are kept (a short stretch between two pauses is never
    /// erased), and the rest of the budget is spread evenly. A map takes them all.
    public func route(maxPoints: Int? = nil) -> [TrackCoordinate]? {
        guard isTracked, points.count >= 2 else { return nil }
        guard let maxPoints, points.count > maxPoints else { return points }
        var kept = Set<Int>()
        for index in points.indices {
            let opens = index == 0 || points[index - 1].segment != points[index].segment
            let closes = index == points.count - 1 || points[index + 1].segment != points[index].segment
            if opens || closes { kept.insert(index) }
        }
        // More segments than the budget: their ends still win over the limit.
        let budget = maxPoints - kept.count
        if budget > 0 {
            let step = Int((Double(points.count) / Double(budget)).rounded(.up))
            kept.formUnion(stride(from: 0, to: points.count, by: step))
        }
        return kept.sorted().map { points[$0] }
    }

    /// How many points a picture of the tracé needs, on Today and in the journal.
    public static let picturePoints = 160
}
