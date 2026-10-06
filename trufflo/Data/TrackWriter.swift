import Foundation
import SwiftData

enum TrackWriteError: Error, Equatable, Sendable {
    case unknownSession
    case sessionNotWritable
    case batchTooLarge
    case invalidDuration
}

struct TrackAppendSummary: Equatable, Sendable {
    let acceptedPoints: Int
    let ignoredPoints: Int
    let rejectedPoints: Int
    let revision: Int
    let recordedPathMeters: Double?
    /// Exactly what was inserted for this batch, in write order. The display layer
    /// draws these, so it never refetches the whole track and never draws a point
    /// the accumulator rejected.
    let insertedPoints: [StoredTrackPoint]
}

struct TrackSnapshot: Equatable, Sendable {
    let phase: WalkPhase
    let quality: WalkQuality
    let confirmedSeconds: TimeInterval
    let recordedPathMeters: Double?
    let measuredEdgeCount: Int
    let pointCount: Int
    let revision: Int
}

/// A point as plain values, so a test or a UI can read the track without any managed
/// object or PersistentIdentifier crossing an actor boundary.
struct StoredTrackPoint: Equatable, Sendable {
    let sequence: Int
    let segment: Int
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

/// The only writer of track points and of a session's aggregate.
///
/// It receives plain Sendable values, never a CLLocationManager and never a managed
/// SwiftData object. Points and their aggregate snapshot are committed in a single
/// bounded transaction, so a crash can lose at most the batch in flight, never half
/// of an aggregate.
@ModelActor
actor TrackWriter {
    /// Bounds the memory one transaction may hold. A larger batch is refused rather
    /// than buffered, which is a saturation signal rather than a leak.
    static let maximumBatchSize = 200

    private var accumulators: [UUID: TrackAccumulator] = [:]

    func appendFixes(_ fixes: [LocationFix], to walkID: UUID) throws -> TrackAppendSummary {
        guard !fixes.isEmpty else {
            let session = try requireSession(walkID)
            return TrackAppendSummary(acceptedPoints: 0, ignoredPoints: 0, rejectedPoints: 0,
                                      revision: session.revision,
                                      recordedPathMeters: session.recordedPathMeters,
                                      insertedPoints: [])
        }
        guard fixes.count <= Self.maximumBatchSize else { throw TrackWriteError.batchTooLarge }

        let session = try requireWritableSession(walkID)
        var accumulator = try accumulator(for: session)

        var accepted = 0
        var ignored = 0
        var rejected = 0
        var inserted: [StoredTrackPoint] = []
        var nextSequence = try headSequence(for: walkID) + 1

        do {
            for fix in fixes {
                let segment: Int
                switch accumulator.ingest(fix) {
                case .anchor(let value):
                    segment = value
                case .accepted(let value, _):
                    segment = value
                case .ignoredDuplicateOrOld:
                    ignored += 1
                    continue
                case .rejected:
                    // A rejection breaks the segment but stores nothing, so the map
                    // never gains a vertex the distance calculation also refused.
                    rejected += 1
                    continue
                }
                modelContext.insert(TrackPointRecord(walkID: walkID, sequence: nextSequence,
                                                     segment: segment,
                                                     latitude: fix.latitude,
                                                     longitude: fix.longitude,
                                                     horizontalAccuracy: fix.horizontalAccuracy,
                                                     timestamp: fix.timestamp))
                inserted.append(StoredTrackPoint(sequence: nextSequence, segment: segment,
                                                 latitude: fix.latitude, longitude: fix.longitude,
                                                 timestamp: fix.timestamp))
                nextSequence += 1
                accepted += 1
            }
            commit(session: session, accumulator: accumulator)
            accumulators[walkID] = accumulator
            try modelContext.save()
        } catch {
            // Never leave half an aggregate behind.
            modelContext.rollback()
            accumulators[walkID] = nil
            throw error
        }

        return TrackAppendSummary(acceptedPoints: accepted, ignoredPoints: ignored,
                                  rejectedPoints: rejected, revision: session.revision,
                                  recordedPathMeters: session.recordedPathMeters,
                                  insertedPoints: inserted)
    }

    /// Stores the confirmed duration supplied by the coordinator. The caller owns the
    /// monotonic clock; this actor never derives an elapsed value from a date.
    func checkpoint(confirmedSeconds: TimeInterval, for walkID: UUID) throws -> TrackSnapshot {
        guard confirmedSeconds.isFinite, confirmedSeconds >= 0 else {
            throw TrackWriteError.invalidDuration
        }
        let session = try requireWritableSession(walkID)
        session.confirmedSeconds = confirmedSeconds
        session.lastCheckpointAt = .now
        session.revision += 1
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
        return try snapshot(forSession: session)
    }

    /// Commits the final snapshot and marks the walk finished. Being on the same actor
    /// as the append path, it necessarily runs after every queued batch.
    func finish(confirmedSeconds: TimeInterval, note: String, for walkID: UUID) throws -> TrackSnapshot {
        guard confirmedSeconds.isFinite, confirmedSeconds >= 0 else {
            throw TrackWriteError.invalidDuration
        }
        let session = try requireSession(walkID)
        guard session.phase != .completed, session.phase != .discarded else {
            throw TrackWriteError.sessionNotWritable
        }
        session.confirmedSeconds = confirmedSeconds
        session.endedAt = .now
        session.phase = .completed
        session.lastCheckpointAt = .now
        session.revision += 1
        if !note.isEmpty { session.note = note }
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
        accumulators[walkID] = nil
        return try snapshot(forSession: session)
    }

    func snapshot(for walkID: UUID) throws -> TrackSnapshot {
        try snapshot(forSession: try requireSession(walkID))
    }

    func breakSegment(for walkID: UUID) throws {
        let session = try requireWritableSession(walkID)
        var accumulator = try accumulator(for: session)
        accumulator.breakSegment()
        accumulators[walkID] = accumulator
    }

    /// Returns plain values: neither a managed object nor its PersistentIdentifier may
    /// leave the actor that owns its context.
    func storedPoints(for walkID: UUID) throws -> [StoredTrackPoint] {
        _ = try requireSession(walkID)
        let descriptor = FetchDescriptor<TrackPointRecord>(
            predicate: #Predicate { $0.walkID == walkID },
            sortBy: [SortDescriptor(\.sequence, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map {
            StoredTrackPoint(sequence: $0.sequence, segment: $0.segment,
                             latitude: $0.latitude, longitude: $0.longitude,
                             timestamp: $0.timestamp)
        }
    }

    private func requireSession(_ walkID: UUID) throws -> WalkRecord {
        let descriptor = FetchDescriptor<WalkRecord>(predicate: #Predicate { $0.id == walkID })
        guard let session = try modelContext.fetch(descriptor).first else {
            throw TrackWriteError.unknownSession
        }
        return session
    }

    private func requireWritableSession(_ walkID: UUID) throws -> WalkRecord {
        let session = try requireSession(walkID)
        guard session.phase == .recording || session.phase == .paused || session.phase == .interrupted else {
            throw TrackWriteError.sessionNotWritable
        }
        return session
    }

    private func commit(session: WalkRecord, accumulator: TrackAccumulator) {
        session.recordedPathMeters = accumulator.measuredDistance
        session.measuredEdgeCount = accumulator.measuredEdgeCount
        session.trackSegmentCount = accumulator.segment
        session.quality = Self.quality(for: session, accumulator: accumulator)
        session.lastCheckpointAt = .now
        session.revision += 1
    }

    private static func quality(for session: WalkRecord, accumulator: TrackAccumulator) -> WalkQuality {
        guard session.source == .gps else { return .manual }
        guard let distance = accumulator.measuredDistance else { return .unavailable }
        return accumulator.isPartial ? .gpsPartial : .gpsRecorded
    }

    /// Rebuilds the filter from the persisted head so a resumed session keeps its own
    /// sequence and never joins coordinates across the interruption.
    private func accumulator(for session: WalkRecord) throws -> TrackAccumulator {
        if let existing = accumulators[session.id] { return existing }
        let walkID = session.id
        let descriptor = FetchDescriptor<TrackPointRecord>(
            predicate: #Predicate { $0.walkID == walkID },
            sortBy: [SortDescriptor(\.sequence, order: .reverse)]
        )
        guard let head = try modelContext.fetch(descriptor).first else {
            return TrackAccumulator()
        }
        let fix = LocationFix(latitude: head.latitude, longitude: head.longitude,
                              horizontalAccuracy: head.horizontalAccuracy,
                              timestamp: head.timestamp)
        return TrackAccumulator(restoredDistanceMeters: session.recordedPathMeters ?? 0,
                                measuredEdgeCount: session.measuredEdgeCount,
                                segment: session.trackSegmentCount,
                                isPartial: session.quality == .gpsPartial,
                                anchor: fix,
                                latestTimestamp: head.timestamp)
    }

    private func headSequence(for walkID: UUID) throws -> Int {
        let descriptor = FetchDescriptor<TrackPointRecord>(
            predicate: #Predicate { $0.walkID == walkID },
            sortBy: [SortDescriptor(\.sequence, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first?.sequence ?? -1
    }

    private func snapshot(forSession session: WalkRecord) throws -> TrackSnapshot {
        let walkID = session.id
        let descriptor = FetchDescriptor<TrackPointRecord>(
            predicate: #Predicate { $0.walkID == walkID }
        )
        return TrackSnapshot(phase: session.phase,
                             quality: session.quality,
                             confirmedSeconds: session.confirmedSeconds,
                             recordedPathMeters: session.recordedPathMeters,
                             measuredEdgeCount: session.measuredEdgeCount,
                             pointCount: try modelContext.fetchCount(descriptor),
                             revision: session.revision)
    }
}