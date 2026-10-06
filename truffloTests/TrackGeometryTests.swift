import Foundation
import Testing
@testable import trufflo

struct TrackGeometryTests {
    private func point(_ segment: Int, _ lat: Double, _ lon: Double) -> TrackCoordinate {
        TrackCoordinate(segment: segment, latitude: lat, longitude: lon)
    }

    @Test("A gap becomes a separate segment, never a drawn edge")
    func gapIsNotBridged() {
        let points = [
            point(1, 48.8500, 2.3500),
            point(1, 48.8501, 2.3501),
            point(2, 48.8600, 2.3600),
            point(2, 48.8601, 2.3601)
        ]
        let segments = TrackGeometry.segments(from: points)
        #expect(segments.count == 2)
        #expect(segments.map(\.segment) == [1, 2])
        #expect(segments.allSatisfy { $0.coordinates.count == 2 })
        #expect(TrackGeometry.drawableSegments(from: points).count == 2)
    }

    @Test("A single anchor is a point, not a path")
    func loneAnchorIsNotDrawable() {
        let points = [point(1, 48.8500, 2.3500)]
        #expect(TrackGeometry.segments(from: points).count == 1)
        #expect(TrackGeometry.drawableSegments(from: points).isEmpty)
    }

    @Test("An empty track frames nothing")
    func emptyTrackHasNoShape() {
        #expect(TrackGeometry.segments(from: []).isEmpty)
        #expect(TrackGeometry.boundingBox(of: []) == nil)
    }

    @Test("The bounding box spans every coordinate with a usable minimum")
    func boundingBoxCoversTheWholeTrack() {
        let points = [
            point(1, 48.8500, 2.3500),
            point(2, 48.8700, 2.3300)
        ]
        let box = try! #require(TrackGeometry.boundingBox(of: points))
        #expect(box.minLat < 48.8500)
        #expect(box.maxLat > 48.8700)
        #expect(box.minLon < 2.3300)
        #expect(box.maxLon > 2.3500)
        #expect(box.maxLat > box.minLat)
        #expect(box.maxLon > box.minLon)
    }

    @Test("One point still frames to a real span")
    func singlePointStillFrames() {
        let box = try! #require(TrackGeometry.boundingBox(of: [point(1, 48.8500, 2.3500)]))
        #expect(box.maxLat > box.minLat)
        #expect(box.maxLon > box.minLon)
    }

    @Test("Segments keep the order the writer produced")
    func segmentOrderIsPreserved() {
        let points = [
            point(2, 48.86, 2.36),
            point(1, 48.85, 2.35),
            point(2, 48.8601, 2.3601)
        ]
        let segments = TrackGeometry.segments(from: points)
        #expect(segments.map(\.segment) == [2, 1])
        #expect(segments[0].coordinates.count == 2)
        #expect(segments[1].coordinates.count == 1)
    }
}
