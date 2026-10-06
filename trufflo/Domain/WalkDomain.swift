import Foundation

public enum WalkPhase: String, Codable, Sendable {
    case recording, paused, interrupted, completed, discarded
}

/// How the walk was captured. A manual entry has no GPS path at all, which is not
/// the same as a GPS walk that recorded a zero distance.
public enum WalkSource: String, Codable, Sendable {
    case manual, gps
}

/// Measurement quality, kept independent from the phase: a finished walk stays
/// finished whatever its quality, and an absent distance is never a measured zero.
public enum WalkQuality: String, Codable, Sendable {
    case gpsRecorded, gpsPartial, manual, unavailable
}

public enum WalkError: Error, Equatable, Sendable {
    case invalidTransition
    case invalidDuration
    case missingDog
    case noteTooLong
}

/// Persist this snapshot after every accepted state change.
/// The coordinator supplies monotonic elapsed time only while its live session exists.
/// Never derive an elapsed delta from a persisted wall-clock date after a cold launch.
public struct WalkProgress: Codable, Equatable, Sendable {
    public private(set) var phase: WalkPhase = .recording
    public private(set) var confirmedSeconds: TimeInterval = 0

    public init() {}

    public mutating func accrue(seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds >= 0,
              (confirmedSeconds + seconds).isFinite else {
            throw WalkError.invalidDuration
        }
        guard phase == .recording else { throw WalkError.invalidTransition }
        confirmedSeconds += seconds
    }

    public mutating func pause() throws {
        if phase == .paused { return }
        guard phase == .recording else { throw WalkError.invalidTransition }
        phase = .paused
    }

    public mutating func resume() throws {
        if phase == .recording { return }
        guard phase == .paused || phase == .interrupted else {
            throw WalkError.invalidTransition
        }
        phase = .recording
    }

    public mutating func finish() throws {
        if phase == .completed { return }
        guard phase != .discarded else { throw WalkError.invalidTransition }
        phase = .completed
    }

    public mutating func discard() throws {
        if phase == .discarded { return }
        guard phase != .completed else { throw WalkError.invalidTransition }
        phase = .discarded
    }

    /// Cold-launch recovery never adds time since the last persisted checkpoint.
    public mutating func recoverAfterColdLaunch() {
        if phase == .recording || phase == .paused { phase = .interrupted }
    }
}

public struct ManualWalkInput: Equatable, Sendable {
    public let dogIDs: [UUID]
    public let durationSeconds: TimeInterval
    public let note: String

    public init(dogIDs: [UUID], durationSeconds: TimeInterval, note: String = "") throws {
        guard !dogIDs.isEmpty else { throw WalkError.missingDog }
        // This is an input sanity limit, not an exercise recommendation.
        guard durationSeconds.isFinite, durationSeconds > 0,
              durationSeconds <= 86_400 else { throw WalkError.invalidDuration }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanNote.count <= 500 else { throw WalkError.noteTooLong }
        self.dogIDs = Array(Set(dogIDs)).sorted { $0.uuidString < $1.uuidString }
        self.durationSeconds = durationSeconds
        self.note = cleanNote
    }
}

/// A correction to a finished walk (PRD F05).
///
/// What can be corrected depends on how the walk was captured. A declared walk
/// can change its duration and end, because both were typed by the person. A
/// recorded walk cannot: its duration and route were measured, and editing them
/// would turn a measurement into a declaration while still calling it GPS. For
/// both, the dogs present and the note can be fixed.
public struct WalkCorrection: Equatable, Sendable {
    public let dogIDs: [UUID]
    public let note: String
    /// Nil for a recorded walk, whose measured duration and end are kept.
    public let durationSeconds: TimeInterval?
    public let endedAt: Date?

    public init(dogIDs: [UUID], note: String, durationSeconds: TimeInterval? = nil,
                endedAt: Date? = nil, now: Date = Date()) throws {
        guard !dogIDs.isEmpty else { throw WalkError.missingDog }
        if let durationSeconds {
            guard durationSeconds.isFinite, durationSeconds > 0,
                  durationSeconds <= 86_400 else { throw WalkError.invalidDuration }
        }
        // A walk cannot end in the future.
        if let endedAt, endedAt > now { throw WalkError.invalidDuration }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanNote.count <= 500 else { throw WalkError.noteTooLong }
        self.dogIDs = Array(Set(dogIDs)).sorted { $0.uuidString < $1.uuidString }
        self.note = cleanNote
        self.durationSeconds = durationSeconds
        self.endedAt = endedAt
    }

    /// Whether this correction changes the measured part of a walk.
    public var touchesTiming: Bool { durationSeconds != nil || endedAt != nil }
}

public struct LocationFix: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

public enum FixOutcome: Equatable, Sendable {
    case anchor(segment: Int)
    case accepted(segment: Int, addedMeters: Double)
    case ignoredDuplicateOrOld
    case rejected
}

/// Initial filter for experiments, not a claim of measured GPS accuracy.
/// Store the outcome/segment alongside accepted coordinates; never join segments in a map.
public struct TrackAccumulator: Sendable {
    public private(set) var distanceMeters: Double = 0
    public private(set) var isPartial = false
    public private(set) var measuredEdgeCount = 0
    public private(set) var segment = 0
    private var anchor: LocationFix?
    private var latestTimestamp: Date?

    // Technical hypothesis values to calibrate in field tests, never dog-health rules.
    public let maximumAccuracy: Double = 35
    public let maximumGap: TimeInterval = 45
    public let maximumSpeed: Double = 12

    public init() {}

    /// Rebuilds the filter from what the single writer already persisted, so a resumed
    /// session continues its own numbering instead of restarting at zero and bridging
    /// coordinates across the interruption.
    public init(restoredDistanceMeters: Double,
                measuredEdgeCount: Int,
                segment: Int,
                isPartial: Bool,
                anchor: LocationFix?,
                latestTimestamp: Date?) {
        self.distanceMeters = restoredDistanceMeters
        self.measuredEdgeCount = measuredEdgeCount
        self.segment = segment
        self.isPartial = isPartial
        self.anchor = anchor
        self.latestTimestamp = latestTimestamp
    }

    public var measuredDistance: Double? {
        measuredEdgeCount > 0 ? distanceMeters : nil
    }

    /// A manual pause is a deliberate break, not necessarily lost GPS data.
    public mutating func breakSegment(markPartial: Bool = false) {
        anchor = nil
        if markPartial { isPartial = true }
    }

    public mutating func ingest(_ fix: LocationFix) -> FixOutcome {
        guard fix.latitude.isFinite, fix.longitude.isFinite,
              (-90...90).contains(fix.latitude), (-180...180).contains(fix.longitude),
              fix.horizontalAccuracy.isFinite, fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= maximumAccuracy,
              fix.timestamp.timeIntervalSince1970.isFinite else {
            breakSegment(markPartial: true)
            return .rejected
        }
        if let latestTimestamp, fix.timestamp <= latestTimestamp {
            return .ignoredDuplicateOrOld
        }
        latestTimestamp = fix.timestamp
        guard let previous = anchor else {
            segment += 1
            anchor = fix
            return .anchor(segment: segment)
        }
        let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
        if seconds > maximumGap {
            isPartial = true
            segment += 1
            anchor = fix
            return .anchor(segment: segment)
        }
        let meters = Self.distance(from: previous, to: fix)
        guard meters.isFinite, seconds > 0, meters / seconds <= maximumSpeed else {
            breakSegment(markPartial: true)
            return .rejected
        }
        // No jitter suppression is claimed here; calibrate it before release.
        distanceMeters += meters
        measuredEdgeCount += 1
        anchor = fix
        return .accepted(segment: segment, addedMeters: meters)
    }

    private static func distance(from a: LocationFix, to b: LocationFix) -> Double {
        let radians = Double.pi / 180
        let lat1 = a.latitude * radians
        let lat2 = b.latitude * radians
        let dLat = (b.latitude - a.latitude) * radians
        let dLon = (b.longitude - a.longitude) * radians
        let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2)
        let clamped = min(1, max(0, h))
        return 6_371_008.8 * 2 * atan2(sqrt(clamped), sqrt(1 - clamped))
    }
}