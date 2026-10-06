import Foundation
import SwiftData
import Testing
@testable import trufflo

@MainActor
struct ActiveWalkViewModelTests {
    @Test("Starting a session initializes view model state properly")
    func testStartSession() throws {
        let container = try PersistenceFactory.make(inMemory: true)
        let repository = JournalRepository(context: container.mainContext)
        let dog = try repository.addDog(DogInput(name: "Oslo", breedKind: "unknown", breedLabel: ""))

        let fakeLocation = FakeLocationProvider()
        let vm = ActiveWalkViewModel(modelContainer: container, locationProvider: fakeLocation)

        vm.startSession(dogIDs: [dog.id])

        #expect(vm.walkID != nil)
        #expect(vm.phase == .recording)
        #expect(vm.dogNames == ["Oslo"])
    }

    @Test("Pausing and resuming updates session state")
    func testPauseAndResume() throws {
        let container = try PersistenceFactory.make(inMemory: true)
        let repository = JournalRepository(context: container.mainContext)
        let dog = try repository.addDog(DogInput(name: "Rex", breedKind: "mixed", breedLabel: ""))

        let fakeLocation = FakeLocationProvider()
        let vm = ActiveWalkViewModel(modelContainer: container, locationProvider: fakeLocation)

        vm.startSession(dogIDs: [dog.id])
        #expect(vm.phase == .recording)

        vm.pause()
        #expect(vm.phase == .paused)

        vm.resume()
        #expect(vm.phase == .recording)
    }

    @Test("Finishing a walk completes the session")
    func testFinishWalk() async throws {
        let container = try PersistenceFactory.make(inMemory: true)
        let repository = JournalRepository(context: container.mainContext)
        let dog = try repository.addDog(DogInput(name: "Bella", breedKind: "unknown", breedLabel: ""))

        let fakeLocation = FakeLocationProvider()
        let vm = ActiveWalkViewModel(modelContainer: container, locationProvider: fakeLocation)

        vm.startSession(dogIDs: [dog.id])
        let started = vm.walkID

        await vm.finish()

        #expect(vm.phase == .completed)
        // The summary screen needs the closed walk's identifier after `walkID`
        // has been released, so finishing hands it over separately.
        #expect(vm.walkID == nil)
        #expect(vm.finishedWalkID == started)
    }
}
