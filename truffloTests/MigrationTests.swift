import Foundation
import SwiftData
import Testing
@testable import trufflo

/// ADR-008: a schema change is validated against a real older store, never by a
/// reinstall that wipes the data. Each test builds a genuine old store on disk,
/// drops the container, then reopens the same file with the current schema and plan.
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
    let dog = FrozenV1V2.DogRecord(name: "Oslo", breedKind: "unknown")
    let walk = FrozenV1V2.WalkRecord.manual(endedAt: Date(timeIntervalSince1970: 5_000),
                                            durationSeconds: 1800, note: "Calme")
    context.insert(dog)
    context.insert(walk)
    context.insert(FrozenV1V2.WalkDogRecord(walkID: walk.id, dogID: dog.id,
                                            dogNameSnapshot: dog.name))
    try context.save()
    writer = nil
}

/// Writes a V2 store exactly as builds before the dog profile fields wrote it:
/// session fields, a track table, one manual walk, one GPS walk with a point.
/// This is the shape every store on disk right now holds.
@MainActor
private func seedLegacyV2Store(at storeURL: URL) throws {
    var writer: ModelContainer? = try PersistenceFactory.makeFixtureStore(
        versioned: SchemaV2.self, at: storeURL)
    guard let context = writer?.mainContext else {
        Issue.record("The legacy V2 fixture store could not be created.")
        return
    }
    let dog = FrozenV1V2.DogRecord(name: "Oslo", breedKind: "known", breedLabel: "Golden")
    let manual = FrozenV1V2.WalkRecord.manual(endedAt: Date(timeIntervalSince1970: 5_000),
                                              durationSeconds: 1800, note: "Calme")
    let gps = FrozenV1V2.WalkRecord.gpsSession(startedAt: Date(timeIntervalSince1970: 9_000))
    context.insert(dog)
    context.insert(manual)
    context.insert(gps)
    context.insert(FrozenV1V2.WalkDogRecord(walkID: manual.id, dogID: dog.id,
                                            dogNameSnapshot: dog.name))
    context.insert(FrozenV1V2.TrackPointRecord(
        walkID: gps.id, sequence: 0, segment: 0,
        latitude: 48.85, longitude: 2.35, horizontalAccuracy: 5,
        timestamp: Date(timeIntervalSince1970: 9_010)))
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

/// The regression for a real lockout: a store written before the dog profile
/// fields existed must open with the current plan, keep its journal, and give
/// the new fields their defaults. Before SchemaV3 existed this threw
/// "Cannot use staged migration with an unknown model version" and the app
/// showed "Journal indisponible" with no way back to the data.
@Test @MainActor func aStoreWrittenBeforeTheDogProfileFieldsStillOpens() throws {
    let directory = try makeV1StoreDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appending(path: "TruffloMigration.store")
    try seedLegacyV2Store(at: storeURL)

    let container = try PersistenceFactory.makeMigrated(at: storeURL)
    let context = ModelContext(container)

    let dogs = try context.fetch(FetchDescriptor<DogRecord>())
    #expect(dogs.count == 1)
    #expect(dogs[0].name == "Oslo")
    #expect(dogs[0].breedLabel == "Golden")
    #expect(dogs[0].ageDescription == "")
    #expect(dogs[0].gender == "unspecified")
    #expect(dogs[0].preferencesNote == "")
    #expect(dogs[0].photoData == nil)

    let walks = try context.fetch(FetchDescriptor<WalkRecord>())
    #expect(walks.count == 2)
    let manual = try #require(walks.first { $0.source == .manual })
    #expect(manual.confirmedSeconds == 1800)
    #expect(manual.note == "Calme")
    #expect(try context.fetch(FetchDescriptor<TrackPointRecord>()).count == 1)
}

/// A store written by builds before walk corrections (V3, with the dog profile
/// fields) must open, keep the profile and the walks, and read every walk as
/// never corrected.
@Test @MainActor func aV3StoreOpensWithEveryWalkUncorrected() throws {
    let directory = try makeV1StoreDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appending(path: "TruffloMigration.store")
    do {
        var writer: ModelContainer? = try PersistenceFactory.makeFixtureStore(
            versioned: SchemaV3.self, at: storeURL)
        let context = try #require(writer?.mainContext)
        let dog = FrozenV3.DogRecord(name: "Oslo", breedKind: "mixed", ageDescription: "3 ans",
                                     gender: "male", preferencesNote: "Tire en laisse",
                                     photoData: Data([1, 2, 3]))
        let walk = FrozenV1V2.WalkRecord.manual(endedAt: Date(timeIntervalSince1970: 7_000),
                                                durationSeconds: 1200, note: "Parc")
        context.insert(dog)
        context.insert(walk)
        context.insert(FrozenV1V2.WalkDogRecord(walkID: walk.id, dogID: dog.id, dogNameSnapshot: "Oslo"))
        try context.save()
        writer = nil
    }

    let container = try PersistenceFactory.makeMigrated(at: storeURL)
    let context = ModelContext(container)
    let dogs = try context.fetch(FetchDescriptor<DogRecord>())
    #expect(dogs.count == 1)
    #expect(dogs[0].ageDescription == "3 ans")
    #expect(dogs[0].preferencesNote == "Tire en laisse")
    #expect(dogs[0].photoData == Data([1, 2, 3]))
    let walks = try context.fetch(FetchDescriptor<WalkRecord>())
    #expect(walks.count == 1)
    #expect(walks[0].confirmedSeconds == 1200)
    #expect(walks[0].correctedAt == nil)
}

/// A store written before routines (V4) opens with its journal and corrections
/// intact and an empty routine table.
@Test @MainActor func aV4StoreOpensWithNoRoutine() throws {
    let directory = try makeV1StoreDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appending(path: "TruffloMigration.store")
    let corrected = Date(timeIntervalSince1970: 8_000)
    do {
        var writer: ModelContainer? = try PersistenceFactory.makeFixtureStore(
            versioned: SchemaV4.self, at: storeURL)
        let context = try #require(writer?.mainContext)
        let dog = DogRecord(name: "Oslo", breedKind: "unknown")
        let walk = WalkRecord.manual(endedAt: Date(timeIntervalSince1970: 7_000), durationSeconds: 900)
        walk.correctedAt = corrected
        context.insert(dog)
        context.insert(walk)
        try context.save()
        writer = nil
    }
    let context = ModelContext(try PersistenceFactory.makeMigrated(at: storeURL))
    #expect(try context.fetch(FetchDescriptor<DogRecord>()).count == 1)
    let walks = try context.fetch(FetchDescriptor<WalkRecord>())
    #expect(walks.count == 1)
    #expect(walks[0].correctedAt == corrected)
    #expect(try context.fetch(FetchDescriptor<RoutineRecord>()).isEmpty)
}

/// The tripwire for unversioned model edits (ADR-008). The live classes are
/// the current schema; if anyone adds, removes or renames a persisted property
/// without freezing the previous shape and adding a version, this dump changes
/// and the suite fails here instead of every store on disk failing to open in
/// the app. Update the expected dump only together with a new schema version.
@Test func theCurrentSchemaShapeIsPinnedSoAnUnversionedModelEditFailsTheSuite() {
    let dump = CurrentSchema.schema.entities
        .map { entity in
            let attributes = entity.attributes.map(\.name).sorted()
                .joined(separator: ",")
            return "\(entity.name){\(attributes)}"
        }
        .sorted()
        .joined(separator: " | ")

    let expected = "DogRecord{ageDescription,breedKind,breedLabel,createdAt,gender,id,name,photoData,preferencesNote}"
        + " | RoutineRecord{dogID,isPaused,minutesPerOuting,outingsPerDay,slotsRaw,updatedAt}"
        + " | TrackPointRecord{horizontalAccuracy,id,latitude,longitude,segment,sequence,timestamp,walkID}"
        + " | WalkDogRecord{dogID,dogNameSnapshot,id,walkID}"
        + " | WalkRecord{confirmedSeconds,correctedAt,endedAt,id,lastCheckpointAt,measuredEdgeCount,note,phaseRaw,qualityRaw,recordedPathMeters,revision,sourceRaw,startedAt,trackSegmentCount}"

    #expect(dump == expected, "CurrentSchema changed. Freeze the previous shape in TruffloSchemas.swift, add a schema version and stage, then update this expectation. Actual dump: \(dump)")
}
