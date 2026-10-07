import Foundation
import Testing
@testable import trufflo

/// What every screen shows of one balade (the tile of Today, the journal row, the
/// walk page, the bilan), decided in one place so the four cannot drift apart.
@Suite("Walk presentation")
struct WalkPresentationTests {
    private let oslo = UUID()
    private let pixel = UUID()
    private let photo = Data([0xFF, 0xD8])
    private let start = Date(timeIntervalSince1970: 1_791_000_000)

    private func presentation(participants: [(UUID, String)],
                              dogs: [WalkPresentation.Dog] = [],
                              points: [TrackCoordinate] = [],
                              isTracked: Bool = true,
                              endedAt: Date? = nil) -> WalkPresentation {
        WalkPresentation(isTracked: isTracked, startedAt: start, endedAt: endedAt,
                         participants: participants.map { .init(dogID: $0.0, name: $0.1) },
                         dogs: dogs, points: points)
    }

    @Test func theTitleNamesTheChiensInAlphabeticalOrder() {
        let walk = presentation(participants: [(pixel, "Pixel"), (oslo, "Oslo")])
        #expect(walk.names == ["Oslo", "Pixel"])
        #expect(walk.title == "Oslo et Pixel")
    }

    @Test func aBaladeWithNoChienLeftIsTitledBalade() {
        #expect(presentation(participants: []).title == "Balade")
    }

    /// The face of a balade is the first chien on it, in the order of "Mes
    /// chiens", that has a photo. A first chien without one does not hide the
    /// second one's face (the walk page used to show none in that case).
    @Test func theFaceIsTheFirstChienOfTheBaladeThatHasAPhoto() {
        let walk = presentation(participants: [(oslo, "Oslo"), (pixel, "Pixel")],
                                dogs: [.init(id: oslo, photo: nil), .init(id: pixel, photo: photo)])
        #expect(walk.leadPhoto == photo)
        #expect(walk.leadName == "Pixel")
    }

    /// A chien deleted from the iPhone keeps its name on the balade, not its face.
    @Test func aChienNoLongerOnTheIPhoneGivesNoFace() {
        let walk = presentation(participants: [(oslo, "Oslo")], dogs: [.init(id: pixel, photo: photo)])
        #expect(walk.leadPhoto == nil)
        #expect(walk.title == "Oslo")
    }

    private func line(_ count: Int) -> [TrackCoordinate] {
        (0..<count).map { TrackCoordinate(segment: 0, latitude: 48.8 + Double($0) * 1e-5, longitude: 2.3) }
    }

    /// A picture of the tracé never draws more than it is asked for, and keeps
    /// where the balade started and where it ended.
    @Test func aThinnedTraceStaysUnderTheLimitAndKeepsBothEnds() {
        let points = line(500)
        let route = presentation(participants: [], points: points).route(maxPoints: 160)
        #expect(route != nil)
        #expect(route!.count <= 160)
        #expect(route!.first == points.first)
        #expect(route!.last == points.last)
    }

    @Test func aMapGetsEveryPoint() {
        #expect(presentation(participants: [], points: line(500)).route()?.count == 500)
    }

    /// A balade ajoutée has no tracé, and a balade suivie that kept a single
    /// point has none worth drawing: never an invented line.
    @Test func noTraceForABaladeAjouteeOrASinglePoint() {
        #expect(presentation(participants: [], points: line(50), isTracked: false).route() == nil)
        #expect(presentation(participants: [], points: line(1)).route() == nil)
    }

    @Test func aBaladeSitsAtItsEndOrAtItsStartWithoutOne() {
        let end = start.addingTimeInterval(1800)
        #expect(presentation(participants: [], endedAt: end).date == end)
        #expect(presentation(participants: []).date == start)
    }

    /// A pause splits the tracé into segments. Thinning a picture keeps the start
    /// and the end of each one, so a short stretch between two pauses is never
    /// erased from the thumbnail.
    @Test func thinningKeepsBothEndsOfEverySegment() {
        let long = (0..<400).map { TrackCoordinate(segment: 0, latitude: 48.8 + Double($0) * 1e-5, longitude: 2.3) }
        let short = (0..<3).map { TrackCoordinate(segment: 1, latitude: 48.9 + Double($0) * 1e-5, longitude: 2.4) }
        let route = presentation(participants: [], points: long + short).route(maxPoints: 40) ?? []
        #expect(route.filter { $0.segment == 1 }.count >= 2)
        #expect(route.contains(short.first!))
        #expect(route.contains(short.last!))
        #expect(route.contains(long.last!))
    }
}
