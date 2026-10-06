import Foundation

/// What the journal export is made of, independent of storage and UI (PRD F07).
///
/// The export is the person's own copy of their data: a summary of every
/// finished walk, and the recorded route of each walk that has one. A manual
/// entry never gets a route file, because it has no coordinates and inventing
/// a GPX for it would be fabricating a path.
public struct ExportPoint: Equatable, Sendable {
    public let segment: Int
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public let timestamp: Date

    public init(segment: Int, latitude: Double, longitude: Double,
                horizontalAccuracy: Double, timestamp: Date) {
        self.segment = segment
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

public struct ExportWalk: Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let durationSeconds: Double
    /// Nil means "not measured", which the export writes as an empty cell, never 0.
    public let distanceMeters: Double?
    public let source: WalkSource
    public let quality: WalkQuality
    public let dogNames: [String]
    public let note: String
    public let points: [ExportPoint]

    public init(id: UUID, startedAt: Date, endedAt: Date?, durationSeconds: Double,
                distanceMeters: Double?, source: WalkSource, quality: WalkQuality,
                dogNames: [String], note: String, points: [ExportPoint]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.source = source
        self.quality = quality
        self.dogNames = dogNames
        self.note = note
        self.points = points
    }

    /// Only a GPS walk with at least two recorded points has a route to give.
    public var hasRoute: Bool { source == .gps && points.count >= 2 }
}

public enum WalkExport {
    /// The columns of the summary, in order. Kept stable so a spreadsheet built
    /// on one export keeps working on the next.
    public static let csvHeader = [
        "id", "debut", "fin", "duree_secondes", "distance_metres",
        "origine", "qualite", "chiens", "note", "fichier_trace"
    ]

    /// A comma-separated summary, one line per walk, oldest first.
    ///
    /// RFC 4180: fields holding a comma, a quote or a line break are quoted, and
    /// quotes inside are doubled. Dates are ISO 8601 in UTC so the file reads the
    /// same whatever the device's time zone.
    public static func csv(_ walks: [ExportWalk]) -> String {
        var lines = [csvHeader.joined(separator: ",")]
        for walk in walks.sorted(by: { $0.startedAt < $1.startedAt }) {
            let fields: [String] = [
                walk.id.uuidString,
                iso8601(walk.startedAt),
                walk.endedAt.map(iso8601) ?? "",
                String(format: "%.0f", walk.durationSeconds),
                walk.distanceMeters.map { String(format: "%.0f", $0) } ?? "",
                walk.source.rawValue,
                walk.quality.rawValue,
                walk.dogNames.joined(separator: " ; "),
                walk.note,
                walk.hasRoute ? gpxFileName(for: walk) : ""
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// The recorded route as GPX 1.1, one `trkseg` per recorded segment so a
    /// pause shows as a break rather than a straight line across it. Nil for a
    /// walk without a route.
    public static func gpx(_ walk: ExportWalk) -> String? {
        guard walk.hasRoute else { return nil }
        let name = walk.dogNames.isEmpty ? "Balade" : "Balade avec " + walk.dogNames.joined(separator: ", ")
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Trufflo" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><time>\(iso8601(walk.startedAt))</time></metadata>
          <trk>
            <name>\(xmlEscape(name))</name>

        """
        var segments: [[ExportPoint]] = []
        var current: Int?
        for point in walk.points {
            if point.segment != current {
                segments.append([])
                current = point.segment
            }
            segments[segments.count - 1].append(point)
        }
        for segment in segments {
            out += "    <trkseg>\n"
            for point in segment {
                // No <hdop>: it is a dilution-of-precision ratio, not the accuracy
                // in metres Core Location gives, and writing one as the other
                // would mislead any tool that reads the file.
                out += String(format: "      <trkpt lat=\"%.7f\" lon=\"%.7f\"><time>%@</time></trkpt>\n",
                              point.latitude, point.longitude, iso8601(point.timestamp))
            }
            out += "    </trkseg>\n"
        }
        out += "  </trk>\n</gpx>\n"
        return out
    }

    /// "balade-2026-10-06-0815-<8 chars of id>.gpx": sortable, unique, readable.
    public static func gpxFileName(for walk: ExportWalk) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "balade-\(formatter.string(from: walk.startedAt))-\(walk.id.uuidString.prefix(8).lowercased()).gpx"
    }

    static func iso8601(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
