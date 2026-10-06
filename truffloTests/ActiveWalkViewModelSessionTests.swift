import Foundation
import SwiftData
import Testing
@testable import trufflo

private final class RecordingAnnouncer: AccessibilityAnnouncing, @unchecked Sendable {
    private(set) var messages: [String] = []
    func announce(_ message: String) {
        messages.append(message)
    }
}

@MainActor
struct ActiveWalkViewModelSessionTests {
    private func makeHarness(
        authorization: LocationAuthorization = .authorizedWhenInUse,
        announcer: AccessibilityAnnouncing = SystemAccessibilityAnnouncer()
    ) throws -> (ModelContainer, JournalRepository, UUID, FakeLocationProvider, ActiveWalkViewModel) {
        let container = try PersistenceFactory.make(inMemory: true)
        let repository = JournalRepository(context: container.mainContext)
        let dog = try repository.addDog(DogInput(name: "Nori", breedKind: "unknown", breedLabel: ""))
        let fake = FakeLocationProvider(authorization: authorization)
        let viewModel = ActiveWalkViewModel(
            modelContainer: container,
            locationProvider: fake,
            accessibilityAnnouncer: announcer
        )
        return (container, repository, dog.id, fake, viewModel)
    }

    private func waitForStop(_ fake: FakeLocationProvider, atLeast count: Int) async -> Bool {
        for _ in 0..<100 {
            if fake.stopCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return fake.stopCount >= count
    }

    /// Real seconds since an instant, measured with the same kind of clock the
    /// view model uses, so a bound can follow the machine instead of assuming it.
    /// `duration(to:)` measures `self → other`, so the start comes first.
    private static func spent(since start: ContinuousClock.Instant) -> TimeInterval {
        let duration = start.duration(to: ContinuousClock.now)
        return TimeInterval(duration.components.seconds)
            + TimeInterval(duration.components.attoseconds) / 1e18
    }

    @Test("A second start keeps the running session and stays silent")
    func doubleStartKeepsOneSession() throws {
        let (container, _, dogID, _, viewModel) = try makeHarness()

        viewModel.startSession(dogIDs: [dogID])
        let first = viewModel.walkID
        viewModel.startSession(dogIDs: [dogID])

        #expect(viewModel.walkID == first)
        #expect(viewModel.errorMessage == nil)

        let walks = try ModelContext(container).fetch(FetchDescriptor<WalkRecord>())
        #expect(walks.count == 1)
    }

    @Test("Confirmed time adds no delta while paused, then resumes from that value")
    func pauseFreezesClockAndResumeRestartsIt() async throws {
        let (container, _, dogID, _, viewModel) = try makeHarness()

        viewModel.startSession(dogIDs: [dogID])
        viewModel.pause()
        let frozen = viewModel.confirmedSeconds

        try await Task.sleep(for: .milliseconds(1100))
        #expect(viewModel.confirmedSeconds == frozen)

        viewModel.resume()
        let resumedAt = ContinuousClock.now
        // Proof that the clock restarted: wait for the confirmed time to grow,
        // rather than assuming a one-second tick landed inside a fixed sleep.
        // A bare `>= frozen` would pass even if resume did nothing.
        var grew = false
        for _ in 0..<100 {
            if viewModel.confirmedSeconds > frozen { grew = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        viewModel.pause()

        #expect(grew, "la reprise doit faire repartir l'horloge")
        // The upper bound follows the measured time since the resume instead of
        // a constant: `frozen + 5` assumed the machine stays close to real
        // time, which a busy runner does not.
        let accrued = Self.spent(since: resumedAt)
        #expect(accrued >= 0)
        #expect(viewModel.confirmedSeconds <= frozen + accrued + 2)

        try? await Task.sleep(for: .milliseconds(50))
        let check = JournalRepository(context: ModelContext(container))
        let paused = try #require(check.walk(id: viewModel.walkID ?? UUID()))
        #expect(paused.phase == .paused)
        #expect(paused.lastCheckpointAt != nil)
    }

    @Test("Pausing and finishing both stop the provider")
    func pauseAndFinishStopTheProvider() async throws {
        let (_, _, dogID, fake, viewModel) = try makeHarness()

        viewModel.startSession(dogIDs: [dogID])
        viewModel.pause()
        #expect(await waitForStop(fake, atLeast: 1))

        viewModel.resume()
        await viewModel.finish()

        #expect(fake.stopCount >= 2)
        #expect(viewModel.phase == .completed)
    }

    @Test("Revoking during a session interrupts it and keeps the confirmed duration")
    func revocationInterruptsWithoutLosingDuration() async throws {
        let (container, _, dogID, fake, viewModel) = try makeHarness()

        viewModel.startSession(dogIDs: [dogID])
        try await Task.sleep(for: .milliseconds(1100))
        fake.revoke()

        #expect(viewModel.phase == .interrupted)
        #expect(await waitForStop(fake, atLeast: 1))
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.confirmedSeconds >= 1.0)

        let check = JournalRepository(context: ModelContext(container))
        #expect(check.walk(id: viewModel.walkID ?? UUID())?.phase == .interrupted)
        #expect(check.walk(id: viewModel.walkID ?? UUID())?.confirmedSeconds ?? 0 >= 1.0)
    }

    @Test("A refused permission creates no session and offers a way out")
    func deniedPermissionCreatesNoSession() throws {
        let (container, _, dogID, _, viewModel) = try makeHarness(authorization: .denied)

        viewModel.startSession(dogIDs: [dogID])

        #expect(viewModel.walkID == nil)
        #expect(viewModel.startBlock == .permissionDenied)
        #expect(viewModel.startBlock?.offersSettings == true)
        #expect(viewModel.startBlock?.message.contains("réglages") == true)

        let walks = try ModelContext(container).fetch(FetchDescriptor<WalkRecord>())
        #expect(walks.isEmpty)
    }

    @Test("A cold relaunch adopts the interrupted walk and keeps the persisted duration")
    func coldRelaunchAdoptsInterruptedWalkWithoutInventingTime() async throws {
        let (container, repository, dogID, _, _) = try makeHarness()
        let walk = try repository.startGpsSession(dogIDs: [dogID])
        try repository.checkpointWalk(walk.id, confirmedSeconds: 42)

        try JournalRepository(context: ModelContext(container)).recoverInterruptedSessions()
        let fake = FakeLocationProvider()
        let relaunched = ActiveWalkViewModel(modelContainer: container, locationProvider: fake)
        relaunched.resumeExisting(walkID: walk.id)

        #expect(relaunched.phase == .interrupted)
        #expect(relaunched.confirmedSeconds == 42)
        #expect(fake.startCount == 0)

        relaunched.resume()
        let resumedAt = ContinuousClock.now
        for _ in 0..<200 where fake.startCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(relaunched.phase == .recording)
        // The clock runs from the last checkpoint, so the ceiling is 42 plus the
        // time that genuinely elapsed since the resume. A constant such as
        // "< 45" only holds on a machine fast enough to reach resume within two
        // seconds, which is exactly what a CI runner is not.
        let ceiling = 42 + Self.spent(since: resumedAt) + 2
        // Guards the measurement itself: `duration(to:)` reads self → other, so
        // an inverted call returns a negative elapsed time and silently turns
        // the ceiling into a floor. That passed locally, where elapsed is near
        // zero, and only failed on a slower runner.
        #expect(Self.spent(since: resumedAt) >= 0)
        #expect(relaunched.confirmedSeconds >= 42)
        #expect(relaunched.confirmedSeconds <= ceiling)
        #expect(fake.startCount == 1)

        await relaunched.finish()

        #expect(relaunched.phase == .completed)
        #expect(fake.stopCount >= 1)
        let stored = try #require(JournalRepository(context: ModelContext(container)).walk(id: walk.id))
        #expect(stored.phase == .completed)
        #expect(stored.confirmedSeconds >= 42)
        #expect(stored.confirmedSeconds <= ceiling)
    }

    @Test("Finishing an interrupted walk saves what was checkpointed and nothing more")
    func finishingInterruptedWalkKeepsCheckpointedDuration() async throws {
        let (container, repository, dogID, _, viewModel) = try makeHarness()
        let walk = try repository.startGpsSession(dogIDs: [dogID])
        try repository.checkpointWalk(walk.id, confirmedSeconds: 42)

        try JournalRepository(context: ModelContext(container)).recoverInterruptedSessions()
        viewModel.resumeExisting(walkID: walk.id)
        #expect(viewModel.phase == .interrupted)

        await viewModel.finish()

        #expect(viewModel.phase == .completed)
        let stored = try #require(JournalRepository(context: ModelContext(container)).walk(id: walk.id))
        #expect(stored.phase == .completed)
        #expect(stored.confirmedSeconds == 42)
    }

    @Test("Approximate accuracy keeps the clock and the journal usable and the distance unavailable")
    func approximateAccuracyKeepsClockAndJournalWithDistanceUnavailable() async throws {
        let (container, _, dogID, fake, viewModel) = try makeHarness()

        viewModel.startSession(dogIDs: [dogID])
        let walkID = try #require(viewModel.walkID)

        // Reduced precision: every fix arrives with ~500 m accuracy, well beyond
        // the 35 m filter, so none of them can contribute to a distance.
        let now = Date()
        for step in 0..<3 {
            fake.emit(latitude: 48.8566, longitude: 2.3522, accuracy: 500,
                      at: now.addingTimeInterval(Double(step - 1) * 5))
        }

        // Three fixes flush one batch; wait until the writer has committed it.
        let check = JournalRepository(context: ModelContext(container))
        var revision = 0
        for _ in 0..<100 {
            revision = check.walk(id: walkID)?.revision ?? 0
            if revision >= 1 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(revision >= 1)
        #expect(viewModel.distanceMeters == nil)

        // The clock never consults the fixes: the duration keeps accruing.
        try await Task.sleep(for: .milliseconds(1100))
        #expect(viewModel.confirmedSeconds >= 1.0)

        await viewModel.finish()

        #expect(viewModel.phase == .completed)
        let stored = try #require(check.walk(id: walkID))
        #expect(stored.phase == .completed)
        #expect(stored.confirmedSeconds >= 1.0)
        #expect(stored.recordedPathMeters == nil)
        #expect(stored.quality == .unavailable)
    }

    @Test("Every session transition announces itself to VoiceOver exactly once")
    func transitionsAnnounceThemselvesOnceEach() async throws {
        let announcer = RecordingAnnouncer()
        let (_, _, dogID, _, viewModel) = try makeHarness(announcer: announcer)
        viewModel.startSession(dogIDs: [dogID])
        viewModel.pause()
        viewModel.resume()
        await viewModel.finish()
        #expect(
            announcer.messages == [
                "Balade en cours",
                "Balade en pause",
                "Balade reprise",
                "Balade terminée"
            ]
        )
    }

    @Test("A refused start stays silent for VoiceOver")
    func deniedStartStaysSilentForVoiceOver() throws {
        let announcer = RecordingAnnouncer()
        let (_, _, _, _, viewModel) = try makeHarness(
            authorization: .denied,
            announcer: announcer
        )
        viewModel.startSession(dogIDs: [])
        #expect(announcer.messages.isEmpty)
        #expect(viewModel.startBlock == .permissionDenied)
    }
}
