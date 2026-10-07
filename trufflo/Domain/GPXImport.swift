import Foundation

/// A GPX file read back into a balade: its points by segment, their times, and
/// the distance they cover (2026-10-07 mock-up, "Depuis un tracé").
///
/// Reads the GPX 1.1 shape the app itself exports (`WalkExport.gpx`) and the
/// common one of other apps: `trk > trkseg > trkpt lat lon > time`. A file with
/// fewer than two timed points is refused: a balade needs a start and an end.
public struct GPXTrack: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let segment: Int
        public let latitude: Double
        public let longitude: Double
        public let time: Date
    }

    public let points: [Point]

    public var startedAt: Date { points.first!.time }
    public var endedAt: Date { points.last!.time }
    public var seconds: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    /// Distance along each segment, never across the gap between two.
    public var meters: Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            pair.0.segment == pair.1.segment ? total + Self.haversine(pair.0, pair.1) : total
        }
    }

    static func haversine(_ a: Point, _ b: Point) -> Double {
        let radius = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }
}

public enum GPXImportError: Error, Equatable {
    case unreadable
    case tooFewPoints
}

public enum GPXImport {
    public static func parse(_ data: Data) throws -> GPXTrack {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw GPXImportError.unreadable }
        let points = reader.points.sorted { $0.time < $1.time }
        guard points.count >= 2, points.last!.time > points.first!.time else { throw GPXImportError.tooFewPoints }
        return GPXTrack(points: points)
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var points: [GPXTrack.Point] = []
        private var segment = -1
        private var pending: (lat: Double, lon: Double)?
        private var text = ""
        private var time: Date?
        private let iso = ISO8601DateFormatter()
        private let isoFraction: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "trkseg": segment += 1
            case "trkpt":
                if segment < 0 { segment = 0 }
                if let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) {
                    pending = (lat, lon)
                    time = nil
                }
            case "time": text = ""
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "time":
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if pending != nil { time = iso.date(from: clean) ?? isoFraction.date(from: clean) }
            case "trkpt":
                if let pending, let time {
                    points.append(.init(segment: segment, latitude: pending.lat, longitude: pending.lon, time: time))
                }
                pending = nil
            default: break
            }
        }
    }
}
