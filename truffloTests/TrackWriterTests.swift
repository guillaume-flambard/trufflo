import Foundation
import SwiftData
import Testing
@testable import trufflo

/// Builds a live GPS session directly in a fresh in-memory store.
@MainActor
private func makeGPFSession() throws -> (ModelContainer, TrackWriter, UUID) {
    let container = try PersistenceFactory.make(inMemory: true)
    let session = WalkRecord.gpsSession(startedAt: Date(timeIntervalSince1970: 1_000))
    container.mainContext.insert(session)
    try container.mainContext.save()
    return (container, TrackWriter(modelContainer: container), session.id)
}

private func fix(_ longitude: Double, seconds: Double, accuracy: Double = 5) -> LocationFix {
    LocationFix(latitude: 48.85, longitude: longitude, horizontalAccuracy: accuracy,
                timestamp: Date(timeIntervalSince1970: 1_000 + seconds))
}

@Test func acceptedPointsAreStoredWithContiguousOrdering() async throws {
    let (_, writer, walkID) = try await makeGPFSession()

    let summary = try await writer.appendFixes([fix(2.35, seconds: 0), fix(2.351, seconds: 10)],
                                               to: walkID)
    #expect(summary.acceptedPoints == 2)

    let points = try await writer.storedPoints(for: walkID)
    #expect(points.map(\.sequence) == [0, 1])
    #expect(points.map(\.segment) == [1, 1])
    #expect(points[0].timestamp < points[1].timestamp)
}

@Test func pointsAndTheirAggregateAreCommittedTogether() async throws {
    let (_, writer, walkID) = try await makeGPFSession()

    let summary = try await writer.appendFixes([fix(2.35, seconds: 0), fix(2.351, seconds: 10)],
                                               to: walkID)
    let snapshot = try await writer.snapshot(for: walkID)

    // One revision per committed transaction, not one per point.
    #expect(summary.revision == 1)
    #expect(snapshot.revision == 1)
    #expect(snapshot.pointCount == 2)
    #expect(snapshot.measuredEdgeCount == 1)
    #expect(snapshot.recordedPathMeters != nil)
    #expect(snapshot.quality == .gpsRecorded)
}

@Test func anOversizedBatchIsRefusedAndWritesNothing() async throws {
    let (_, writer, walkID) = try await makeGPFSession()

    let oversized = (0..<(TrackWriter.maximumBatchSize + 1)).map {
        fix(2.35 + Double($0) * 0.00001, seconds: Double($0) * 5)
    }
    await #expect(throws: TrackWriteError.batchTooLarge) {
        try await writer.appendFixes(oversized, to: walkID)
    }

    // Nothing partial survived, and the session is still writable.
    let snapshot = try await writer.snapshot(for: walkID)
    #expect(snapshot.pointCount == 0)
    #expect(snapshot.recordedPathMeters == nil)
    #expect(snapshot.revision == 0)

    let summary = try await writer.appendFixes([fix(2.35, seconds: 0)], to: walkID)
    #expect(summary.acceptedPoints == 1)
}

@Test func aRefusedBatchDoesNotCorruptTheNextOne() async throws {
    let (_, writer, walkID) = try await makeGPFSession()
    _ = try await writer.appendFixes([fix(2.35, seconds: 0)], to: walkID)

    await #expect(throws: TrackWriteError.batchTooLarge) {
        try await writer.appendFixes(
            (0..<(TrackWriter.maximumBatchSize + 1)).map {
                fix(2.36 + Double($0) * 0.00001, seconds: 100 + Double($0) * 5)
            },
            to: walkID)
    }

    let points = try await writer.storedPoints(for: walkID)
    #expect(points.map(\.sequence) == [0])
    let summary = try await writer.appendFixes([fix(2.351, seconds: 10)], to: walkID)
    #expect(summary.acceptedPoints == 1)
    let after = try await writer.storedPoints(for: walkID)
    #expect(after.map(\.sequence) == [0, 1])
}

@Test func lateAndDuplicateFixesAreIgnoredWithoutWritingPoints() async throws {
    let (_, writer, walkID) = try await makeGPFSession()
    _ = try await writer.appendFixes([fix(2.35, seconds: 0), fix(2.351, seconds: 10)], to: walkID)

    let summary = try await writer.appendFixes([fix(2.352, seconds: 10), fix(2.353, seconds: 5)],
                                               to: walkID)
    #expect(summary.ignoredPoints == 2)
    #expect(summary.acceptedPoints == 0)

    let points = try await writer.storedPoints(for: walkID)
    #expect(points.count == 2)
}

@Test func aGapOpensANewSegmentAndMarksTheWalkPartial() async throws {
    let (_, writer, walkID) = try await makeGPFSession()
    _ = try await writer.appendFixes([fix(2.35, seconds: 0), fix(2.351, seconds: 10)], to: walkID)

    // A gap beyond the filter threshold must not be joined.
    _ = try await writer.appendFixes([fix(2.352, seconds: 120)], to: walkID)

    let points = try await writer.storedPoints(for: walkID)
    #expect(points.map(\.segment) == [1, 1, 2])
    let snapshot = try await writer.snapshot(for: walkID)
    #expect(snapshot.quality == .gpsPartial)
    // Distance covers only the first segment; the gap adds nothing.
    #expect(snapshot.measuredEdgeCount == 1)
}

@Test func aWalkWithNoAcceptedEdgeReportsUnavailableRatherThanZero() async throws {
    let (_, writer, walkID) = try await makeGPFSession()

    _ = try await writer.appendFixes([fix(2.35, seconds: 0)], to: walkID)
    let snapshot = try await writer.snapshot(for: walkID)

    #expect(snapshot.recordedPathMeters == nil)
    #expect(snapshot.quality == .unavailable)
}

@Test func checkpointStoresTheConfirmedDurationSuppliedByTheCaller() async throws {
    let (_, writer, walkID) = try await makeGPFSession()

    let snapshot = try await writer.checkpoint(confirmedSeconds: 300, for: walkID)
    #expect(snapshot.confirmedSeconds == 300)

    await #expect(throws: TrackWriteError.invalidDuration) {
        try await writer.checkpoint(confirmedSeconds: .nan, for: walkID)
    }
    await #expect(throws: TrackWriteError.invalidDuration) {
        try await writer.checkpoint(confirmedSeconds: -1, for: walkID)
    }

    let after = try await writer.snapshot(for: walkID)
    #expect(after.confirmedSeconds == 300)
}

@Test func finishWaitsForTheQueuedPointsAndClosesTheWalk() async throws {
    let (_, writer, walkID) = try await makeGPFSession()

    let summary = try await writer.appendFixes([fix(2.35, seconds: 0), fix(2.351, seconds: 10)],
                                               to: walkID)
    let finished = try await writer.finish(confirmedSeconds: 600, note: "Calme", for: walkID)

    #expect(summary.acceptedPoints == 2)
    #expect(finished.phase == .completed)
    #expect(finished.confirmedSeconds == 600)
    #expect(finished.pointCount == 2)
}

@Test func aFinishedWalkRefusesFurtherWrites() async throws {
    let (_, writer, walkID) = try await makeGPFSession()
    _ = try await writer.finish(confirmedSeconds: 60, note: "", for: walkID)

    await #expect(throws: TrackWriteError.sessionNotWritable) {
        try await writer.appendFixes([fix(2.35, seconds: 0)], to: walkID)
    }
    await #expect(throws: TrackWriteError.sessionNotWritable) {
        try await writer.finish(confirmedSeconds: 90, note: "", for: walkID)
    }
}

@Test func anUnknownSessionIsRejected() async throws {
    let (_, writer, _) = try await makeGPFSession()
    await #expect(throws: TrackWriteError.unknownSession) {
        try await writer.appendFixes([fix(2.35, seconds: 0)], to: UUID())
    }
}

/// A fresh writer stands in for a cold launch: it must continue the persisted
/// numbering and must not bridge coordinates across the interruption.
@Test @MainActor func aNewWriterResumesFromPersistedStateWithoutBridgingTheGap() async throws {
    let (container, writer, walkID) = try makeGPFSession()
    _ = try await writer.appendFixes([fix(2.35, seconds: 0), fix(2.351, seconds: 10)], to: walkID)
    _ = try await writer.finish(confirmedSeconds: 600, note: "", for: walkID)

    // Re-open the same walk as an interrupted session, as a cold launch would.
    let context = container.mainContext
    let stored = try #require(
        try context.fetch(FetchDescriptor<WalkRecord>(predicate: #Predicate { $0.id == walkID })).first)
    stored.phase = .interrupted
    stored.endedAt = nil
    try context.save()

    let resumedWriter = TrackWriter(modelContainer: container)
    let summary = try await resumedWriter.appendFixes([fix(2.36, seconds: 600)], to: walkID)

    #expect(summary.acceptedPoints == 1)
    let points = try await resumedWriter.storedPoints(for: walkID)
    // Sequence continues at 2 and the new point opens a new segment: no line is drawn
    // across the interruption.
    #expect(points.map(\.sequence) == [0, 1, 2])
    #expect(points.map(\.segment) == [1, 1, 2])
}