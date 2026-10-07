import Foundation

extension WalkPresentation {
    /// A stored balade as the screens show it. `dogs` in the order of "Mes chiens"
    /// (`createdAt`), `points` in recording order.
    init(walk: WalkRecord, participants: [WalkDogRecord], dogs: [DogRecord], points: [TrackPointRecord]) {
        self.init(isTracked: walk.source != .manual,
                  startedAt: walk.startedAt, endedAt: walk.endedAt,
                  participants: participants.map { .init(dogID: $0.dogID, name: $0.dogNameSnapshot) },
                  dogs: dogs.map { .init(id: $0.id, photo: $0.photoData) },
                  points: points.map { .init(segment: $0.segment, latitude: $0.latitude, longitude: $0.longitude) })
    }
}
