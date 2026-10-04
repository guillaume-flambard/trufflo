import Foundation
import Testing
@testable import trufflo

@Test func recordingAccruesConfirmedTime() throws {
    var walk = WalkProgress()
    try walk.accrue(seconds: 30)
    try walk.accrue(seconds: 15)
    #expect(walk.confirmedSeconds == 45)
}

@Test func pauseIsIdempotentAndCannotAccrue() throws {
    var walk = WalkProgress()
    try walk.accrue(seconds: 30)
    try walk.pause()
    try walk.pause()
    #expect(throws: WalkError.invalidTransition) { try walk.accrue(seconds: 10) }
    #expect(walk.confirmedSeconds == 30)
}

@Test func resumePreservesExistingDuration() throws {
    var walk = WalkProgress()
    try walk.accrue(seconds: 20)
    try walk.pause()
    try walk.resume()
    try walk.resume()
    try walk.accrue(seconds: 10)
    #expect(walk.confirmedSeconds == 30)
}

@Test func coldLaunchDoesNotInventElapsedTime() throws {
    var walk = WalkProgress()
    try walk.accrue(seconds: 42)
    let data = try JSONEncoder().encode(walk)
    var restored = try JSONDecoder().decode(WalkProgress.self, from: data)
    restored.recoverAfterColdLaunch()
    #expect(restored.phase == .interrupted)
    #expect(restored.confirmedSeconds == 42)
}

@Test func pausedSessionIsInterruptedOnColdLaunch() throws {
    var walk = WalkProgress()
    try walk.pause()
    walk.recoverAfterColdLaunch()
    #expect(walk.phase == .interrupted)
}

@Test func completedSessionStaysCompletedAfterColdLaunch() throws {
    var walk = WalkProgress()
    try walk.finish()
    try walk.finish()
    walk.recoverAfterColdLaunch()
    #expect(walk.phase == .completed)
    #expect(throws: WalkError.invalidTransition) { try walk.resume() }
}

@Test func discardedSessionCannotFinish() throws {
    var walk = WalkProgress()
    try walk.discard()
    #expect(throws: WalkError.invalidTransition) { try walk.finish() }
}

@Test(arguments: [-1.0, Double.nan, Double.infinity])
func invalidElapsedTimeIsRejected(seconds: Double) {
    var walk = WalkProgress()
    #expect(throws: WalkError.invalidDuration) { try walk.accrue(seconds: seconds) }
}

@Test func manualWalkDeduplicatesDogsWithoutMultiplyingDuration() throws {
    let dogA = UUID()
    let dogB = UUID()
    let input = try ManualWalkInput(dogIDs: [dogA, dogA, dogB], durationSeconds: 1800)
    #expect(input.dogIDs.count == 2)
    #expect(input.durationSeconds == 1800)
}

@Test func manualWalkRequiresADog() {
    #expect(throws: WalkError.missingDog) {
        try ManualWalkInput(dogIDs: [], durationSeconds: 600)
    }
}

@Test(arguments: [0.0, -1.0, Double.nan, Double.infinity, 86_401.0])
func manualWalkRejectsInvalidDuration(seconds: Double) {
    #expect(throws: WalkError.invalidDuration) {
        try ManualWalkInput(dogIDs: [UUID()], durationSeconds: seconds)
    }
}

@Test func manualNoteIsTrimmedAndLimited() throws {
    let input = try ManualWalkInput(dogIDs: [UUID()], durationSeconds: 60, note: "  Calme  ")
    #expect(input.note == "Calme")
    #expect(throws: WalkError.noteTooLong) {
        try ManualWalkInput(dogIDs: [UUID()], durationSeconds: 60, note: String(repeating: "a", count: 501))
    }
}

private func fix(_ longitude: Double, seconds: Double, accuracy: Double = 5) -> LocationFix {
    LocationFix(latitude: 0, longitude: longitude, horizontalAccuracy: accuracy,
                timestamp: Date(timeIntervalSince1970: 1_000 + seconds))
}

@Test func distanceIsUnavailableBeforeAnEdgeExists() {
    var track = TrackAccumulator()
    #expect(track.measuredDistance == nil)
    #expect(track.ingest(fix(0, seconds: 0)) == .anchor(segment: 1))
    #expect(track.measuredDistance == nil)
}

@Test func validGeometryAddsApproximateDistance() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    _ = track.ingest(fix(0.0001, seconds: 5))
    #expect(abs(track.distanceMeters - 11.1195) < 0.01)
    #expect(track.measuredEdgeCount == 1)
    #expect(!track.isPartial)
}

@Test func samePositionProducesARealZeroDistanceEdge() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    _ = track.ingest(fix(0, seconds: 5))
    #expect(track.measuredDistance == 0)
}

@Test func badAccuracyDoesNotBridgeUnknownMotion() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    #expect(track.ingest(fix(0.0001, seconds: 5, accuracy: 500)) == .rejected)
    #expect(track.ingest(fix(0.0002, seconds: 10)) == .anchor(segment: 2))
    #expect(track.distanceMeters == 0)
    #expect(track.isPartial)
}

@Test func largeTimeGapStartsANewSegment() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    #expect(track.ingest(fix(0.0001, seconds: 60)) == .anchor(segment: 2))
    #expect(track.measuredDistance == nil)
    #expect(track.isPartial)
}

@Test func impossibleJumpIsRejected() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    #expect(track.ingest(fix(10, seconds: 1)) == .rejected)
    #expect(track.distanceMeters == 0)
}

@Test func oldAndDuplicateFixesAreIgnored() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 10))
    #expect(track.ingest(fix(0.001, seconds: 10)) == .ignoredDuplicateOrOld)
    #expect(track.ingest(fix(0.001, seconds: 9)) == .ignoredDuplicateOrOld)
    #expect(!track.isPartial)
}

@Test func manualPauseDoesNotConnectCoordinates() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    track.breakSegment()
    #expect(track.ingest(fix(0.0001, seconds: 5)) == .anchor(segment: 2))
    #expect(!track.isPartial)
    #expect(track.measuredDistance == nil)
}

@Test func invalidCoordinatesAreRejected() {
    var track = TrackAccumulator()
    let point = LocationFix(latitude: 91, longitude: 0, horizontalAccuracy: 5, timestamp: Date())
    #expect(track.ingest(point) == .rejected)
    #expect(track.isPartial)
}

@Test func nonFiniteMetadataIsRejected() {
    var track = TrackAccumulator()
    #expect(track.ingest(fix(0, seconds: 0, accuracy: .nan)) == .rejected)
    #expect(track.ingest(fix(.infinity, seconds: 0)) == .rejected)
}