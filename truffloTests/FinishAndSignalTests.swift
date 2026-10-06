import Foundation
import SwiftData
import Testing
@testable import trufflo

/// The two minor findings of the adversarial pass (E-035). Both were reported as
/// cosmetic, and both are the kind of defect a person notices immediately in the
/// hand: an error over a walk that just saved, and a lamp claiming a signal that
/// is no longer being collected.
@MainActor
struct FinishAndSignalTests {
    private func makeHarness() throws -> (ModelContainer, JournalRepository, UUID,
                                          FakeLocationProvider, ActiveWalkViewModel) {
        let container = try PersistenceFactory.make(inMemory: true)
        let repository = JournalRepository(context: container.mainContext)
        let dog = try repository.addDog(DogInput(name: "Nori", breedKind: "unknown", breedLabel: ""))
        let fake = FakeLocationProvider()
        let viewModel = ActiveWalkViewModel(modelContainer: container, locationProvider: fake)
        return (container, repository, dog.id, fake, viewModel)
    }

    @Test("F4: finishing twice keeps one saved walk and raises no error")
    func doubleFinishIsSilent() async throws {
        let (container, _, dogID, fake, viewModel) = try makeHarness()
        viewModel.startSession(dogIDs: [dogID])
        try await Task.sleep(for: .milliseconds(1100))
        let walkID = try #require(viewModel.walkID)

        await viewModel.finish()
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.phase == .completed)

        // The second tap is what a user does on a slow network or a nervous
        // thumb. It must not report a failure over a walk that just saved.
        await viewModel.finish()
        #expect(viewModel.errorMessage == nil, "une seconde fin ne doit pas signaler d'erreur")
        #expect(viewModel.phase == .completed)

        let check = JournalRepository(context: ModelContext(container))
        let stored = try #require(check.walk(id: walkID))
        #expect(stored.phase == .completed)
        #expect(stored.endedAt != nil)
        #expect(stored.confirmedSeconds >= 1.0)
        // One walk, one set of links: the duplicate did not create a second row.
        let walks = try ModelContext(container).fetch(FetchDescriptor<WalkRecord>())
        #expect(walks.count == 1)
        #expect(fake.stopCount >= 1)
    }

    @Test("F5: pausing turns the signal lamp off")
    func pauseStopsReportingAnActiveSignal() async throws {
        let (_, _, dogID, fake, viewModel) = try makeHarness()
        viewModel.startSession(dogIDs: [dogID])

        let now = Date()
        for step in 0..<3 {
            fake.emit(latitude: 48.8566, longitude: 2.3522, accuracy: 5,
                      at: now.addingTimeInterval(Double(step) * 5))
        }
        #expect(viewModel.isLocationActive, "un point de position doit allumer le voyant")

        viewModel.pause()

        // pause() stops the provider from a Task, so the lamp goes dark a beat
        // later. Asserting synchronously would test the scheduler, not the app.
        var lampOff = false
        for _ in 0..<100 {
            if !viewModel.isLocationActive { lampOff = true; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(lampOff, "après une pause, aucune collecte n'a lieu")
        #expect(viewModel.phase == .paused)

        // And it stays off while paused: a late fix from before the stop must
        // not light it again.
        fake.emit(latitude: 48.8570, longitude: 2.3525, accuracy: 5, at: now.addingTimeInterval(30))
        #expect(!viewModel.isLocationActive)
    }

    @Test("F5: finishing also leaves the lamp off")
    func finishStopsReportingAnActiveSignal() async throws {
        let (_, _, dogID, fake, viewModel) = try makeHarness()
        viewModel.startSession(dogIDs: [dogID])
        let now = Date()
        for step in 0..<3 {
            fake.emit(latitude: 48.8566, longitude: 2.3522, accuracy: 5,
                      at: now.addingTimeInterval(Double(step) * 5))
        }
        #expect(viewModel.isLocationActive)

        await viewModel.finish()

        #expect(!viewModel.isLocationActive)
    }
}