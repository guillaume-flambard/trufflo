import Foundation
import SwiftData
import Testing
@testable import trufflo

@MainActor
private func makeJournal() throws -> (ModelContainer, JournalRepository, UUID) {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    let dog = DogRecord(name: "Oslo", breedKind: "unknown")
    container.mainContext.insert(dog)
    try container.mainContext.save()
    return (container, repository, dog.id)
}

@MainActor
@Test func gpsSessionStartsOnceAndReturnsTheSameWalk() throws {
    let (_, repository, dogID) = try makeJournal()
    let first = try repository.startGpsSession(dogIDs: [dogID])
    let second = try repository.startGpsSession(dogIDs: [dogID])
    #expect(first.id == second.id)
    #expect(repository.liveWalk()?.id == first.id)
    #expect(first.source == .gps)
    #expect(first.phase == .recording)
    #expect(first.confirmedSeconds == 0)
}

@MainActor
@Test func gpsSessionRecordsItsParticipantsOnce() throws {
    let (_, repository, dogID) = try makeJournal()
    let walk = try repository.startGpsSession(dogIDs: [dogID])
    _ = try repository.startGpsSession(dogIDs: [dogID])
    #expect(repository.participants(walkID: walk.id).count == 1)
}

@MainActor
@Test func gpsSessionRefusesAnUnknownProfileInsteadOfNamingNobody() throws {
    let (_, repository, _) = try makeJournal()
    #expect(throws: JournalError.profileMissing) {
        try repository.startGpsSession(dogIDs: [UUID()])
    }
    #expect(repository.liveWalk() == nil)
}

@MainActor
@Test func pauseThenResumeKeepsPhaseAndDuration() throws {
    let (_, repository, dogID) = try makeJournal()
    let walk = try repository.startGpsSession(dogIDs: [dogID])

    try repository.pauseWalk(walk.id, confirmedSeconds: 120)
    #expect(repository.walk(id: walk.id)?.phase == .paused)
    #expect(repository.walk(id: walk.id)?.confirmedSeconds == 120)

    try repository.resumeWalk(walk.id)
    #expect(repository.walk(id: walk.id)?.phase == .recording)
    #expect(repository.walk(id: walk.id)?.confirmedSeconds == 120)
    #expect(repository.liveWalk()?.id == walk.id)
}

@MainActor
@Test func pauseFromTheWrongPhaseIsRefused() throws {
    let (_, repository, dogID) = try makeJournal()
    let walk = try repository.startGpsSession(dogIDs: [dogID])
    #expect(throws: WalkError.invalidTransition) {
        try repository.resumeWalk(walk.id)
    }
    try repository.pauseWalk(walk.id, confirmedSeconds: 30)
    #expect(throws: WalkError.invalidTransition) {
        try repository.pauseWalk(walk.id, confirmedSeconds: 60)
    }
}

@MainActor
@Test func interruptionKeepsTheConfirmedDurationAndClearsTheLiveWalk() throws {
    let (_, repository, dogID) = try makeJournal()
    let walk = try repository.startGpsSession(dogIDs: [dogID])
    try repository.interruptWalk(walk.id, confirmedSeconds: 45)
    let stored = repository.walk(id: walk.id)
    #expect(stored?.phase == .interrupted)
    #expect(stored?.confirmedSeconds == 45)
    #expect(repository.liveWalk() == nil)
}

@MainActor
@Test func aFinishedSessionDoesNotBlockTheNextOne() async throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    let dog = DogRecord(name: "Nala", breedKind: "mixed")
    container.mainContext.insert(dog)
    try container.mainContext.save()

    let first = try repository.startGpsSession(dogIDs: [dog.id])
    let writer = TrackWriter(modelContainer: container)
    _ = try await writer.finish(confirmedSeconds: 60, note: "", for: first.id)

    let reopened = JournalRepository(context: ModelContext(container))
    #expect(reopened.liveWalk() == nil)

    let second = try reopened.startGpsSession(dogIDs: [dog.id])
    #expect(second.id != first.id)
    #expect(reopened.walk(id: first.id)?.phase == .completed)
}

@MainActor
@Test func fakeProviderDrivesTheSeamWithoutCoreLocation() async throws {
    let provider = FakeLocationProvider()
    var received: [LocationServiceEvent] = []
    provider.setHandler { event in received.append(event) }

    await provider.start()
    #expect(provider.startCount == 1)
    #expect(provider.started)
    #expect(provider.states == [.acquiring])

    let moment = Date(timeIntervalSince1970: 1_700_000_000)
    provider.emit(latitude: 48.85, longitude: 2.35, accuracy: 5, at: moment)
    #expect(provider.states == [.acquiring, .active])
    #expect(received.count == 3)
    #expect(received[2] == .fix(LocationFix(latitude: 48.85, longitude: 2.35,
                                            horizontalAccuracy: 5, timestamp: moment)))

    await provider.stop()
    #expect(provider.stopCount == 1)
    #expect(provider.started == false)
}

@MainActor
@Test func coldLaunchInterruptsALiveSessionWithoutAddingTime() throws {
    let (container, repository, dogID) = try makeJournal()
    let walk = try repository.startGpsSession(dogIDs: [dogID])
    try repository.checkpointWalk(walk.id, confirmedSeconds: 42)

    let relaunched = JournalRepository(context: ModelContext(container))
    try relaunched.recoverInterruptedSessions()

    let stored = relaunched.walk(id: walk.id)
    #expect(stored?.phase == .interrupted)
    #expect(stored?.confirmedSeconds == 42)
    #expect(relaunched.liveWalk() == nil)
}

@MainActor
@Test func coldLaunchLeavesFinishedAndAbandonedWalksAlone() throws {
    let (container, repository, dogID) = try makeJournal()
    let live = try repository.startGpsSession(dogIDs: [dogID])
    try repository.checkpointWalk(live.id, confirmedSeconds: 10)

    let finished = WalkRecord.manual(endedAt: .now, durationSeconds: 1_800)
    let abandoned = WalkRecord(startedAt: .now.addingTimeInterval(-3_600),
                               confirmedSeconds: 60,
                               phase: .discarded,
                               source: .gps)
    container.mainContext.insert(finished)
    container.mainContext.insert(abandoned)
    try container.mainContext.save()

    try JournalRepository(context: ModelContext(container)).recoverInterruptedSessions()

    let check = JournalRepository(context: ModelContext(container))
    #expect(check.walk(id: live.id)?.phase == .interrupted)
    #expect(check.walk(id: finished.id)?.phase == .completed)
    #expect(check.walk(id: finished.id)?.confirmedSeconds == 1_800)
    #expect(check.walk(id: abandoned.id)?.phase == .discarded)
    #expect(check.walk(id: abandoned.id)?.confirmedSeconds == 60)
}

@MainActor
@Test func anInterruptedSessionResumesOnItsPersistedDuration() throws {
    let (container, repository, dogID) = try makeJournal()
    let walk = try repository.startGpsSession(dogIDs: [dogID])
    try repository.checkpointWalk(walk.id, confirmedSeconds: 42)

    let relaunched = JournalRepository(context: ModelContext(container))
    try relaunched.recoverInterruptedSessions()
    try relaunched.resumeWalk(walk.id)

    #expect(relaunched.walk(id: walk.id)?.phase == .recording)
    #expect(relaunched.walk(id: walk.id)?.confirmedSeconds == 42)
    #expect(relaunched.liveWalk()?.id == walk.id)
}
