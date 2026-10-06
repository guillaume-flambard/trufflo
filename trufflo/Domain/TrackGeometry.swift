import Foundation

/// One coordinate as the map layer needs it, with the segment it belongs to.
///
/// Deliberately not `CLLocationCoordinate2D`: MapKit is a display dependency and
/// the shape of a track must stay testable in milliseconds, without it.
public struct TrackCoordinate: Equatable, Sendable {
    public let segment: Int
    public let latitude: Double
    public let longitude: Double

    public init(segment: Int, latitude: Double, longitude: Double) {
        self.segment = segment
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A contiguous run of coordinates. A segment is never joined to the next one:
/// the gap between them is a pause or a signal loss, and drawing through it would
/// draw a road the dogs never walked.
public struct TrackSegmentShape: Equatable, Sendable {
    public let segment: Int
    public let coordinates: [TrackCoordinate]

    public init(segment: Int, coordinates: [TrackCoordinate]) {
        self.segment = segment
        self.coordinates = coordinates
    }
}

public enum TrackGeometry {
    /// Splits points into segments in the order given, dropping a segment that has
    /// no coordinate at all. Points must already be ordered by sequence.
    public static func segments(from points: [TrackCoordinate]) -> [TrackSegmentShape] {
        var order: [Int] = []
        var grouped: [Int: [TrackCoordinate]] = [:]
        for point in points {
            if grouped[point.segment] == nil { order.append(point.segment) }
            grouped[point.segment, default: []].append(point)
        }
        return order.compactMap { segment in
            guard let coordinates = grouped[segment] else { return nil }
            return TrackSegmentShape(segment: segment, coordinates: coordinates)
        }
    }

    /// Bounding box of every coordinate, or nil when there is nothing to frame.
    /// A single point still frames, with a small span so MapKit does not zoom to a
    /// degenerate rectangle.
    public static func boundingBox(of points: [TrackCoordinate]) -> (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double)? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in points.dropFirst() {
            minLat = Swift.min(minLat, point.latitude)
            maxLat = Swift.max(maxLat, point.latitude)
            minLon = Swift.min(minLon, point.longitude)
            maxLon = Swift.max(maxLon, point.longitude)
        }
        let minimumSpan = 0.002
        return (minLat: minLat - minimumSpan, minLon: minLon - minimumSpan,
                maxLat: maxLat + minimumSpan, maxLon: maxLon + minimumSpan)
    }

    /// Only a run of two or more coordinates can be drawn as a line. A lone anchor
    /// is a point, and pretending it is a path would invent geometry.
    public static func drawableSegments(from points: [TrackCoordinate]) -> [TrackSegmentShape] {
        segments(from: points).filter { $0.coordinates.count >= 2 }
    }
}
