import Foundation
import SwiftData
import Testing
@testable import trufflo

@MainActor
@Test func editingAProfileChangesTheProfileAndNothingElse() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let repository = JournalRepository(context: context)

    let dog = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    try repository.addManualWalk(
        try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 900),
        endedAt: .now
    )

    try repository.updateDog(dog.id, with: try DogInput(name: "Oslothe",
                                                        breedKind: "known",
                                                        breedLabel: "Berger australien"))

    let verification = ModelContext(container)
    let dogs = try verification.fetch(FetchDescriptor<DogRecord>())
    let links = try verification.fetch(FetchDescriptor<WalkDogRecord>())
    #expect(dogs.count == 1)
    #expect(dogs[0].name == "Oslothe")
    #expect(dogs[0].breedLabel == "Berger australien")
    #expect(links.count == 1)
    // The walk keeps the name it recorded at the time, not the renamed profile.
    #expect(links[0].dogNameSnapshot == "Oslo")
}

@MainActor
@Test func deletingAProfileKeepsItsWalkLinks() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let repository = JournalRepository(context: context)

    let dog = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    try repository.addManualWalk(
        try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 900),
        endedAt: .now
    )
    try repository.deleteDog(dog.id)

    let verification = ModelContext(container)
    #expect(try verification.fetch(FetchDescriptor<DogRecord>()).isEmpty)
    let walks = try verification.fetch(FetchDescriptor<WalkRecord>())
    let links = try verification.fetch(FetchDescriptor<WalkDogRecord>())
    #expect(walks.count == 1)
    #expect(links.count == 1)
    #expect(links[0].dogNameSnapshot == "Oslo")
}

@MainActor
@Test func updatingAMissingProfileFails() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    let missing = UUID()
    #expect(throws: JournalError.profileMissing) {
        try repository.updateDog(missing, with: try DogInput(name: "Ghost", breedKind: "unknown"))
    }
}

@MainActor
@Test func deletingAMissingProfileFails() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    #expect(throws: JournalError.profileMissing) {
        try repository.deleteDog(UUID())
    }
}

@MainActor
@Test func deletingAWalkRemovesItsLinksAndPoints() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let repository = JournalRepository(context: context)

    let dog = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let walk = try repository.addManualWalk(
        try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 900),
        endedAt: .now
    )
    let kept = try repository.addManualWalk(
        try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 600),
        endedAt: .now
    )
    context.insert(TrackPointRecord(walkID: walk.id, sequence: 0, segment: 1,
                                    latitude: 48.8566, longitude: 2.3522,
                                    horizontalAccuracy: 8, timestamp: .now))
    try context.save()

    try repository.deleteWalk(walk.id)

    let verification = ModelContext(container)
    let walks = try verification.fetch(FetchDescriptor<WalkRecord>())
    let links = try verification.fetch(FetchDescriptor<WalkDogRecord>())
    let points = try verification.fetch(FetchDescriptor<TrackPointRecord>())
    #expect(walks.map(\.id) == [kept.id])
    #expect(links.count == 1)
    #expect(links[0].walkID == kept.id)
    #expect(points.isEmpty)
}

@MainActor
@Test func deletingAMissingWalkFails() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    #expect(throws: JournalError.walkMissing) {
        try repository.deleteWalk(UUID())
    }
}

/// The erasure previously skipped track points, which was invisible only while
/// no walk had any. The gap reappears the day GPS recording ships.
@MainActor
@Test func erasingEverythingAlsoRemovesTrackPoints() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let repository = JournalRepository(context: context)

    let dog = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let walk = try repository.addManualWalk(
        try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 900),
        endedAt: .now
    )
    context.insert(TrackPointRecord(walkID: walk.id, sequence: 0, segment: 1,
                                    latitude: 48.8566, longitude: 2.3522,
                                    horizontalAccuracy: 8, timestamp: .now))
    try context.save()

    try repository.eraseAll()

    let verification = ModelContext(container)
    #expect(try verification.fetch(FetchDescriptor<DogRecord>()).isEmpty)
    #expect(try verification.fetch(FetchDescriptor<WalkRecord>()).isEmpty)
    #expect(try verification.fetch(FetchDescriptor<WalkDogRecord>()).isEmpty)
    #expect(try verification.fetch(FetchDescriptor<TrackPointRecord>()).isEmpty)
}

@MainActor
@Test func addingAWalkForAVanishedProfileWritesNothing() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let repository = JournalRepository(context: context)

    let dog = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let vanished = dog.id
    try repository.deleteDog(vanished)

    #expect(throws: JournalError.profileMissing) {
        try repository.addManualWalk(try ManualWalkInput(dogIDs: [vanished], durationSeconds: 900),
                                     endedAt: .now)
    }

    let verification = ModelContext(container)
    #expect(try verification.fetch(FetchDescriptor<WalkRecord>()).isEmpty)
    #expect(try verification.fetch(FetchDescriptor<WalkDogRecord>()).isEmpty)
}
