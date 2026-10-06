import Foundation
import SwiftData
import Testing
@testable import trufflo

private let now = Date(timeIntervalSince1970: 1_791_300_000)

@Test func aCorrectionNeedsADogAndAPlausibleTiming() {
    #expect(throws: WalkError.missingDog) { try WalkCorrection(dogIDs: [], note: "", now: now) }
    #expect(throws: WalkError.invalidDuration) {
        try WalkCorrection(dogIDs: [UUID()], note: "", durationSeconds: 0, now: now)
    }
    #expect(throws: WalkError.invalidDuration) {
        try WalkCorrection(dogIDs: [UUID()], note: "", durationSeconds: .infinity, now: now)
    }
    #expect(throws: WalkError.invalidDuration) {
        try WalkCorrection(dogIDs: [UUID()], note: "", endedAt: now.addingTimeInterval(60), now: now)
    }
    #expect(throws: WalkError.noteTooLong) {
        try WalkCorrection(dogIDs: [UUID()], note: String(repeating: "a", count: 501), now: now)
    }
}

@MainActor
private func journal() throws -> (ModelContainer, JournalRepository, DogRecord, DogRecord) {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    let oslo = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let mira = try repository.addDog(try DogInput(name: "Mirabelle", breedKind: "unknown"))
    return (container, repository, oslo, mira)
}

@MainActor
@Test func correctingADeclaredWalkChangesItsTimingDogsAndNoteAndMarksIt() throws {
    let (container, repository, oslo, mira) = try journal()
    let walk = try repository.addManualWalk(try ManualWalkInput(dogIDs: [oslo.id], durationSeconds: 600),
                                            endedAt: now.addingTimeInterval(-3600))
    #expect(walk.correctedAt == nil)

    let end = now.addingTimeInterval(-7200)
    try repository.correctWalk(walk.id, with: try WalkCorrection(
        dogIDs: [oslo.id, mira.id], note: "  Plus long que noté  ",
        durationSeconds: 2400, endedAt: end, now: now), at: now)

    let fresh = ModelContext(container)
    let stored = try #require(try fresh.fetch(FetchDescriptor<WalkRecord>()).first)
    #expect(stored.confirmedSeconds == 2400)
    #expect(stored.endedAt == end)
    #expect(stored.startedAt == end.addingTimeInterval(-2400))
    #expect(stored.note == "Plus long que noté")
    #expect(stored.correctedAt == now)
    let names = try fresh.fetch(FetchDescriptor<WalkDogRecord>()).map(\.dogNameSnapshot).sorted()
    #expect(names == ["Mirabelle", "Oslo"])
}

@MainActor
@Test func aRecordedWalkKeepsItsMeasuredTiming() throws {
    let (container, repository, oslo, mira) = try journal()
    let context = container.mainContext
    let gps = WalkRecord(startedAt: now.addingTimeInterval(-1800), endedAt: now.addingTimeInterval(-600),
                         confirmedSeconds: 1200, phase: .completed, source: .gps, quality: .gpsRecorded)
    gps.recordedPathMeters = 900
    context.insert(gps)
    context.insert(WalkDogRecord(walkID: gps.id, dogID: oslo.id, dogNameSnapshot: "Oslo"))
    try context.save()

    #expect(throws: WalkError.invalidTransition) {
        try repository.correctWalk(gps.id, with: try WalkCorrection(
            dogIDs: [oslo.id], note: "", durationSeconds: 60, now: now), at: now)
    }
    // The refused correction changed nothing.
    #expect(gps.correctedAt == nil)

    try repository.correctWalk(gps.id, with: try WalkCorrection(
        dogIDs: [mira.id], note: "C'était Mirabelle", now: now), at: now)
    #expect(gps.confirmedSeconds == 1200)
    #expect(gps.recordedPathMeters == 900)
    #expect(gps.note == "C'était Mirabelle")
    #expect(gps.correctedAt == now)
    let links = try context.fetch(FetchDescriptor<WalkDogRecord>())
    #expect(links.map(\.dogNameSnapshot) == ["Mirabelle"])
}

@MainActor
@Test func aWalkStillInProgressCannotBeCorrected() throws {
    let (_, repository, oslo, _) = try journal()
    let live = try repository.startGpsSession(dogIDs: [oslo.id])
    #expect(throws: JournalError.walkMissing) {
        try repository.correctWalk(live.id, with: try WalkCorrection(dogIDs: [oslo.id], note: "", now: now), at: now)
    }
}

@MainActor
@Test func aDeletedProfileKeepsItsHistoricalNameWhenItStaysOnTheWalk() throws {
    let (container, repository, oslo, mira) = try journal()
    let walk = try repository.addManualWalk(try ManualWalkInput(dogIDs: [oslo.id, mira.id], durationSeconds: 600),
                                            endedAt: now.addingTimeInterval(-60))
    try repository.deleteDog(mira.id)
    try repository.correctWalk(walk.id, with: try WalkCorrection(
        dogIDs: [oslo.id, mira.id], note: "Note corrigée", now: now), at: now)
    let names = try ModelContext(container).fetch(FetchDescriptor<WalkDogRecord>())
        .map(\.dogNameSnapshot).sorted()
    #expect(names == ["Mirabelle", "Oslo"])
}
