import Foundation
import SwiftData
import Testing
@testable import trufflo

@MainActor
@Test func manualWalkHasOneDurationAndTwoParticipants() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let a = DogRecord(name: "Oslo", breedKind: "unknown")
    let b = DogRecord(name: "Nala", breedKind: "mixed")
    context.insert(a)
    context.insert(b)
    let walk = WalkRecord.manual(endedAt: .now, durationSeconds: 1800)
    context.insert(walk)
    context.insert(WalkDogRecord(walkID: walk.id, dogID: a.id, dogNameSnapshot: a.name))
    context.insert(WalkDogRecord(walkID: walk.id, dogID: b.id, dogNameSnapshot: b.name))
    try context.save()
    let walks = try context.fetch(FetchDescriptor<WalkRecord>())
    let participants = try context.fetch(FetchDescriptor<WalkDogRecord>())
    #expect(walks.count == 1)
    #expect(walks[0].confirmedSeconds == 1800)
    #expect(participants.count == 2)
}

@MainActor
@Test func journalSurvivesAReopenedStore() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let dog = DogRecord(name: "Oslo", breedKind: "unknown")
    context.insert(dog)
    let walk = WalkRecord.manual(endedAt: .now, durationSeconds: 1800, note: "Calme")
    context.insert(walk)
    context.insert(WalkDogRecord(walkID: walk.id, dogID: dog.id, dogNameSnapshot: dog.name))
    try context.save()

    // A fresh context over the same store must see the saved journal.
    let verification = ModelContext(container)
    let walks = try verification.fetch(FetchDescriptor<WalkRecord>())
    let dogs = try verification.fetch(FetchDescriptor<DogRecord>())
    let links = try verification.fetch(FetchDescriptor<WalkDogRecord>())
    #expect(walks.count == 1)
    #expect(dogs.count == 1)
    #expect(links.count == 1)
    #expect(walks[0].note == "Calme")
    #expect(walks[0].source == .manual)
}

@MainActor
@Test func globalErasureRemovesWalksLinksAndProfiles() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let dog = DogRecord(name: "Oslo", breedKind: "unknown")
    context.insert(dog)
    let walk = WalkRecord.manual(endedAt: .now, durationSeconds: 900)
    context.insert(walk)
    context.insert(WalkDogRecord(walkID: walk.id, dogID: dog.id, dogNameSnapshot: dog.name))
    try context.save()

    for link in try context.fetch(FetchDescriptor<WalkDogRecord>()) { context.delete(link) }
    for stored in try context.fetch(FetchDescriptor<WalkRecord>()) { context.delete(stored) }
    for stored in try context.fetch(FetchDescriptor<DogRecord>()) { context.delete(stored) }
    try context.save()

    let verification = ModelContext(container)
    #expect(try verification.fetch(FetchDescriptor<WalkRecord>()).isEmpty)
    #expect(try verification.fetch(FetchDescriptor<WalkDogRecord>()).isEmpty)
    #expect(try verification.fetch(FetchDescriptor<DogRecord>()).isEmpty)
}

@MainActor
@Test func manualWalkIsRejectedBeforeAnyPartialWrite() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    context.insert(DogRecord(name: "Oslo", breedKind: "unknown"))
    try context.save()

    #expect(throws: WalkError.invalidDuration) {
        try ManualWalkInput(dogIDs: [UUID()], durationSeconds: 0)
    }
    let verification = ModelContext(container)
    #expect(try verification.fetch(FetchDescriptor<WalkRecord>()).isEmpty)
    #expect(try verification.fetch(FetchDescriptor<WalkDogRecord>()).isEmpty)
}

/// The M0 gate: a real on-disk store, not an in-memory one, must still hold the
/// journal after the writing container is gone. Uses a temporary directory so the
/// developer's actual journal is never touched by a test run.
@MainActor
@Test func journalSurvivesAReopenedOnDiskStore() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "trufflo-on-disk-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let storeURL = directory.appending(path: "TruffloFixture.store")
    let schema = CurrentSchema.schema
    let migrationPlan = TruffloMigrationPlan.self

    func makeStore() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TruffloOnDiskFixture",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: migrationPlan,
                                  configurations: [configuration])
    }

    var writer: ModelContainer? = try makeStore()
    guard let writingContext = writer?.mainContext else {
        Issue.record("The on-disk fixture container could not be created.")
        return
    }
    let dog = DogRecord(name: "Oslo", breedKind: "unknown")
    writingContext.insert(dog)
    let walk = WalkRecord.manual(endedAt: .now, durationSeconds: 1800, note: "Calme")
    writingContext.insert(walk)
    writingContext.insert(WalkDogRecord(walkID: walk.id, dogID: dog.id, dogNameSnapshot: dog.name))
    try writingContext.save()

    // Simulate a cold launch: drop the writing container entirely before reopening.
    writer = nil
    #expect(FileManager.default.fileExists(atPath: storeURL.path))

    let reopened = try makeStore()
    let verification = ModelContext(reopened)
    let walks = try verification.fetch(FetchDescriptor<WalkRecord>())
    let dogs = try verification.fetch(FetchDescriptor<DogRecord>())
    let links = try verification.fetch(FetchDescriptor<WalkDogRecord>())
    #expect(dogs.count == 1)
    #expect(dogs[0].name == "Oslo")
    #expect(walks.count == 1)
    #expect(walks[0].confirmedSeconds == 1800)
    #expect(walks[0].note == "Calme")
    #expect(links.count == 1)
    #expect(links[0].dogNameSnapshot == "Oslo")
}