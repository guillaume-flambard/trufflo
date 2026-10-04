import Foundation
import SwiftData
import Testing
@testable import trufflo

/// ADR-008: a schema change is validated against a real older store, never by a
/// reinstall that wipes the data. Each test builds a genuine V1 store on disk, drops
/// the container, then reopens the same file with the current schema and plan.
@MainActor
private func makeV1StoreDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "trufflo-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Writes a V1 journal, then destroys the writing container so nothing survives in
/// memory. Returns the store URL to be reopened by the current schema.
@MainActor
private func seedV1Store(at storeURL: URL) throws {
    var writer: ModelContainer? = try PersistenceFactory.makeFixtureStore(
        versioned: SchemaV1.self, at: storeURL)
    guard let context = writer?.mainContext else {
        Issue.record("The V1 fixture store could not be created.")
        return
    }
    let dog = DogRecord(name: "Oslo", breedKind: "unknown")
    let walk = WalkRecord.manual(endedAt: Date(timeIntervalSince1970: 5_000),
                                  durationSeconds: 1800, note: "Calme")
    context.insert(dog)
    context.insert(walk)
    context.insert(WalkDogRecord(walkID: walk.id, dogID: dog.id, dogNameSnapshot: dog.name))
    try context.save()
    writer = nil
}

@Test @MainActor func aV1JournalSurvivesTheMoveToV2WithoutLosingAnything() throws {
    let directory = try makeV1StoreDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appending(path: "TruffloMigration.store")
    try seedV1Store(at: storeURL)

    let container = try PersistenceFactory.makeMigrated(at: storeURL)
    let context = ModelContext(container)
    let dogs = try context.fetch(FetchDescriptor<DogRecord>())
    let walks = try context.fetch(FetchDescriptor<WalkRecord>())
    let links = try context.fetch(FetchDescriptor<WalkDogRecord>())

    #expect(dogs.count == 1)
    #expect(dogs[0].name == "Oslo")
    #expect(walks.count == 1)
    #expect(walks[0].confirmedSeconds == 1800)
    #expect(walks[0].note == "Calme")
    #expect(walks[0].source == .manual)
    #expect(walks[0].quality == .manual)
    #expect(walks[0].phase == .completed)
    #expect(links.count == 1)
    #expect(links[0].dogNameSnapshot == "Oslo")
}

@Test @MainActor func aMigratedManualWalkStillHasNoPointsAndNoDistance() throws {
    let directory = try makeV1StoreDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appending(path: "TruffloMigration.store")
    try seedV1Store(at: storeURL)

    let container = try PersistenceFactory.makeMigrated(at: storeURL)
    let context = ModelContext(container)
    let walk = try #require(try context.fetch(FetchDescriptor<WalkRecord>()).first)

    #expect(try context.fetch(FetchDescriptor<TrackPointRecord>()).isEmpty)
    #expect(walk.recordedPathMeters == nil)
    #expect(walk.measuredEdgeCount == 0)
}

@Test @MainActor func theMigratedStoreAcceptsNewTrackPoints() async throws {
    let directory = try makeV1StoreDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appending(path: "TruffloMigration.store")
    try seedV1Store(at: storeURL)

    let container = try PersistenceFactory.makeMigrated(at: storeURL)
    let context = container.mainContext
    let gps = WalkRecord.gpsSession(startedAt: Date(timeIntervalSince1970: 9_000))
    context.insert(gps)
    try context.save()

    let writer = TrackWriter(modelContainer: container)
    let fix = LocationFix(latitude: 48.85, longitude: 2.35, horizontalAccuracy: 5,
                          timestamp: Date(timeIntervalSince1970: 9_010))
    let summary = try await writer.appendFixes([fix], to: gps.id)
    #expect(summary.acceptedPoints == 1)
    let points = try await writer.storedPoints(for: gps.id)
    #expect(points.count == 1)

    // The migrated manual walk is untouched by the new one.
    #expect(try context.fetch(FetchDescriptor<WalkRecord>()).count == 2)
}

@Test @MainActor func reopeningAnAlreadyMigratedStoreIsIdempotent() throws {
    let directory = try makeV1StoreDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appending(path: "TruffloMigration.store")
    try seedV1Store(at: storeURL)

    _ = try PersistenceFactory.makeMigrated(at: storeURL)
    let again = try PersistenceFactory.makeMigrated(at: storeURL)
    let context = ModelContext(again)
    #expect(try context.fetch(FetchDescriptor<WalkRecord>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<DogRecord>()).count == 1)
}