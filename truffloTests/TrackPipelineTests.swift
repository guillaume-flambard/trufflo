import Foundation
import SwiftData
import Testing
@testable import trufflo

@MainActor
struct TrackPipelineTests {
    private func makeHarness() throws -> (ModelContainer, JournalRepository, UUID, FakeLocationProvider, ActiveWalkViewModel) {
        let container = try PersistenceFactory.make(inMemory: true)
        let repository = JournalRepository(context: container.mainContext)
        let dog = try repository.addDog(DogInput(name: "Oslo", breedKind: "unknown", breedLabel: ""))
        let fake = FakeLocationProvider()
        let viewModel = ActiveWalkViewModel(modelContainer: container, locationProvider: fake)
        return (container, repository, dog.id, fake, viewModel)
    }

    @Test("Resuming re-anchors instead of drawing an edge across the pause")
    func resumingReanchorsInsteadOfBridgingTheGap() async throws {
        let (container, _, dogID, fake, viewModel) = try makeHarness()
        let origin = Date()

        viewModel.startSession(dogIDs: [dogID])
        fake.emit(latitude: 48.8500, longitude: 2.3500, accuracy: 5, at: origin)
        fake.emit(latitude: 48.8501, longitude: 2.3500, accuracy: 5, at: origin.addingTimeInterval(1))
        fake.emit(latitude: 48.8502, longitude: 2.3500, accuracy: 5, at: origin.addingTimeInterval(2))
        for _ in 0..<100 {
            if viewModel.distanceMeters != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let before = try #require(viewModel.distanceMeters)

        viewModel.pause()
        viewModel.resume()
        try await Task.sleep(for: .milliseconds(150))

        fake.emit(latitude: 48.8511, longitude: 2.3500, accuracy: 5, at: origin.addingTimeInterval(12))
        fake.emit(latitude: 48.8512, longitude: 2.3500, accuracy: 5, at: origin.addingTimeInterval(13))
        fake.emit(latitude: 48.8513, longitude: 2.3500, accuracy: 5, at: origin.addingTimeInterval(14))
        for _ in 0..<100 {
            if let distance = viewModel.distanceMeters, distance >= before + 20 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        let walkID = try #require(viewModel.walkID)
        let walk = try #require(JournalRepository(context: ModelContext(container)).walk(id: walkID))
        #expect(walk.trackSegmentCount == 2)
        #expect(walk.measuredEdgeCount == 4)
        #expect(viewModel.distanceMeters ?? 0 < before + 60)
    }

    @Test("Fixes delivered after an interruption never reach the track")
    func fixesDeliveredAfterAnInterruptionAreIgnored() async throws {
        let (container, _, dogID, fake, viewModel) = try makeHarness()
        let origin = Date()

        viewModel.startSession(dogIDs: [dogID])
        fake.emit(latitude: 48.8500, longitude: 2.3500, accuracy: 5, at: origin)
        fake.emit(latitude: 48.8501, longitude: 2.3500, accuracy: 5, at: origin.addingTimeInterval(1))
        fake.emit(latitude: 48.8502, longitude: 2.3500, accuracy: 5, at: origin.addingTimeInterval(2))
        for _ in 0..<100 {
            if viewModel.distanceMeters != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        fake.revoke()
        #expect(viewModel.phase == .interrupted)
        let deliveredBefore = fake.emitted.count

        fake.emit(latitude: 48.8600, longitude: 2.3600, accuracy: 5, at: origin.addingTimeInterval(30))
        fake.emit(latitude: 48.8601, longitude: 2.3600, accuracy: 5, at: origin.addingTimeInterval(31))
        fake.emit(latitude: 48.8602, longitude: 2.3600, accuracy: 5, at: origin.addingTimeInterval(32))
        try await Task.sleep(for: .milliseconds(150))

        #expect(fake.emitted.count == deliveredBefore + 3)
        #expect(viewModel.phase == .interrupted)

        let walkID = try #require(viewModel.walkID)
        let walk = try #require(JournalRepository(context: ModelContext(container)).walk(id: walkID))
        #expect(walk.phase == .interrupted)
        #expect(walk.trackSegmentCount == 1)
        #expect(walk.measuredEdgeCount == 2)
        #expect(walk.quality == .gpsRecorded)
        #expect(viewModel.distanceMeters ?? 0 < 30)
    }
}
