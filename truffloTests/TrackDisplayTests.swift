import Foundation
import SwiftData
import Testing
@testable import trufflo

/// The map draws `ActiveWalkViewModel.trackPoints`. These tests pin the contract
/// between what the writer stored and what the map is handed, because a mismatch
/// would draw a path the distance never measured.
@MainActor
struct TrackDisplayTests {
    private func makeHarness() throws -> (ModelContainer, JournalRepository, UUID, FakeLocationProvider, ActiveWalkViewModel) {
        let container = try PersistenceFactory.make(inMemory: true)
        let repository = JournalRepository(context: container.mainContext)
        let dog = try repository.addDog(DogInput(name: "Oslo", breedKind: "unknown", breedLabel: ""))
        let fake = FakeLocationProvider()
        let viewModel = ActiveWalkViewModel(modelContainer: container, locationProvider: fake)
        return (container, repository, dog.id, fake, viewModel)
    }

    private func waitForTrack(_ viewModel: ActiveWalkViewModel, minimum count: Int) async {
        for _ in 0..<150 {
            if viewModel.trackPoints.count >= count { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// The writer is fed in batches of three, so a batch of three is what makes a
    /// flush observable without reaching into the model's batching.
    private func emitBatch(_ fake: FakeLocationProvider, from index: Int,
                           startingAt origin: Date, count: Int = 3) {
        for step in 0..<count {
            fake.emit(latitude: 48.8500 + Double(index + step) * 0.0001, longitude: 2.3500,
                      accuracy: 5, at: origin.addingTimeInterval(TimeInterval(index + step)))
        }
    }

    @Test("The live path holds exactly the points the writer stored")
    func livePathMatchesPersistedPoints() async throws {
        let (container, _, dogID, fake, viewModel) = try makeHarness()
        let origin = Date()
        viewModel.startSession(dogIDs: [dogID])

        emitBatch(fake, from: 0, startingAt: origin)
        await waitForTrack(viewModel, minimum: 3)

        let walkID = try #require(viewModel.walkID)
        let stored = try await TrackWriter(modelContainer: container).storedPoints(for: walkID)
        #expect(stored.count == 3)
        #expect(viewModel.trackPoints.count == stored.count)
        #expect(viewModel.trackPoints.map(\.latitude) == stored.map(\.latitude))
        #expect(viewModel.trackPoints.map(\.segment) == stored.map(\.segment))
        #expect(TrackGeometry.drawableSegments(from: viewModel.trackPoints).count == 1)
    }

    @Test("A fix the accumulator rejects adds no vertex")
    func rejectedFixIsNotDrawn() async throws {
        let (container, _, dogID, fake, viewModel) = try makeHarness()
        let origin = Date()
        viewModel.startSession(dogIDs: [dogID])

        fake.emit(latitude: 48.8500, longitude: 2.3500, accuracy: 5, at: origin)
        fake.emit(latitude: 48.8501, longitude: 2.3500, accuracy: 5, at: origin.addingTimeInterval(1))
        // 900 m of accuracy: refused by the filter before it can become geometry.
        fake.emit(latitude: 48.8600, longitude: 2.3500, accuracy: 900, at: origin.addingTimeInterval(2))
        fake.emit(latitude: 48.8502, longitude: 2.3500, accuracy: 5, at: origin.addingTimeInterval(3))
        await waitForTrack(viewModel, minimum: 3)
        try await Task.sleep(for: .milliseconds(120))

        let walkID = try #require(viewModel.walkID)
        let stored = try await TrackWriter(modelContainer: container).storedPoints(for: walkID)
        #expect(viewModel.trackPoints.count == stored.count)
        #expect(viewModel.trackPoints.allSatisfy { $0.latitude < 48.86 })
    }

    @Test("A pause splits the drawn path instead of joining it")
    func pauseSplitsTheDrawnPath() async throws {
        let (container, _, dogID, fake, viewModel) = try makeHarness()
        let origin = Date()
        viewModel.startSession(dogIDs: [dogID])

        // Three fixes, so the first segment is stored as its own batch.
        emitBatch(fake, from: 0, startingAt: origin)
        await waitForTrack(viewModel, minimum: 3)

        viewModel.pause()
        viewModel.resume()
        try await Task.sleep(for: .milliseconds(150))

        emitBatch(fake, from: 30, startingAt: origin.addingTimeInterval(30))
        await waitForTrack(viewModel, minimum: 6)

        let segments = TrackGeometry.drawableSegments(from: viewModel.trackPoints)
        #expect(segments.count == 2)
        #expect(segments[0].coordinates.count == 3)
        #expect(segments[1].coordinates.count == 3)
    }

    @Test("A relaunch shows the path recorded before it, not an empty map")
    func relaunchRestoresTheRecordedPath() async throws {
        let (container, repository, dogID, fake, viewModel) = try makeHarness()
        let origin = Date()
        viewModel.startSession(dogIDs: [dogID])
        emitBatch(fake, from: 0, startingAt: origin)
        await waitForTrack(viewModel, minimum: 3)

        try repository.interruptWalk(try #require(viewModel.walkID), confirmedSeconds: 12)

        let restored = ActiveWalkViewModel(modelContainer: container,
                                           locationProvider: FakeLocationProvider())
        restored.resumeExisting(walkID: try #require(viewModel.walkID))
        await waitForTrack(restored, minimum: 3)
        #expect(restored.trackPoints.count == 3)
        #expect(TrackGeometry.drawableSegments(from: restored.trackPoints).count == 1)
    }

    @Test("Finishing clears the live path, so a next walk does not inherit it")
    func finishingClearsTheLivePath() async throws {
        let (_, _, dogID, fake, viewModel) = try makeHarness()
        let origin = Date()
        viewModel.startSession(dogIDs: [dogID])
        emitBatch(fake, from: 0, startingAt: origin)
        await waitForTrack(viewModel, minimum: 3)

        await viewModel.finish()
        #expect(viewModel.trackPoints.isEmpty)
    }
}
