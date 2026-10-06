import Foundation
import SwiftData

// MARK: - Frozen legacy shapes (ADR-008)
//
// A VersionedSchema only freezes a shape if it declares its OWN model types.
// Pointing a version at the live classes in Models.swift means every property
// added there silently rewrites that version's identity, and every store
// written by an older build fails with "Cannot use staged migration with an
// unknown model version" — the journal becomes unreachable, with no path back.
//
// When a @Model gains, loses or changes a persisted property:
//   1. Copy the current live shape into FrozenV1V2-style frozen types (it
//      becomes the previous version as it was written to disk),
//   2. point that VersionedSchema at the frozen copies,
//   3. add a new VersionedSchema that references the live classes,
//   4. add the matching lightweight stage below, and
//   5. update the golden schema dump test in MigrationTests.
// Never validate a model change by reinstalling (ADR-008, DATA-CONTRACTS).
enum FrozenV1V2 {
    /// DogRecord before the profile fields existed: no age, gender,
    /// preferences note or photo. The shape every pre-profile store holds.
    @Model
    final class DogRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var breedKind: String
        var breedLabel: String
        var createdAt: Date

        init(id: UUID = UUID(), name: String, breedKind: String,
             breedLabel: String = "") {
            self.id = id
            self.name = name
            self.breedKind = breedKind
            self.breedLabel = breedLabel
            self.createdAt = .now
        }
    }

    @Model
    final class WalkRecord {
        @Attribute(.unique) var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var confirmedSeconds: Double
        var phaseRaw: String
        var sourceRaw: String
        var qualityRaw: String
        var recordedPathMeters: Double?
        var measuredEdgeCount: Int
        var trackSegmentCount: Int
        var revision: Int
        var lastCheckpointAt: Date
        var note: String

        init(id: UUID = UUID(),
             startedAt: Date,
             endedAt: Date? = nil,
             confirmedSeconds: TimeInterval = 0,
             phase: WalkPhase = .recording,
             source: WalkSource = .manual,
             quality: WalkQuality = .unavailable,
             note: String = "") {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.confirmedSeconds = confirmedSeconds
            self.phaseRaw = phase.rawValue
            self.sourceRaw = source.rawValue
            self.qualityRaw = quality.rawValue
            self.recordedPathMeters = nil
            self.measuredEdgeCount = 0
            self.trackSegmentCount = 0
            self.revision = 0
            self.lastCheckpointAt = startedAt
            self.note = note
        }

        static func manual(endedAt: Date, durationSeconds: TimeInterval,
                           note: String = "") -> WalkRecord {
            WalkRecord(startedAt: endedAt.addingTimeInterval(-durationSeconds),
                       endedAt: endedAt,
                       confirmedSeconds: durationSeconds,
                       phase: .completed,
                       source: .manual,
                       quality: .manual,
                       note: note)
        }

        static func gpsSession(startedAt: Date) -> WalkRecord {
            WalkRecord(startedAt: startedAt,
                       endedAt: nil,
                       confirmedSeconds: 0,
                       phase: .recording,
                       source: .gps,
                       quality: .unavailable)
        }
    }

    @Model
    final class WalkDogRecord {
        @Attribute(.unique) var id: UUID
        var walkID: UUID
        var dogID: UUID
        var dogNameSnapshot: String

        init(walkID: UUID, dogID: UUID, dogNameSnapshot: String) {
            self.id = UUID()
            self.walkID = walkID
            self.dogID = dogID
            self.dogNameSnapshot = dogNameSnapshot
        }
    }

    @Model
    final class TrackPointRecord {
        @Attribute(.unique) var id: UUID
        var walkID: UUID
        var sequence: Int
        var segment: Int
        var latitude: Double
        var longitude: Double
        var horizontalAccuracy: Double
        var timestamp: Date

        init(id: UUID = UUID(),
             walkID: UUID,
             sequence: Int,
             segment: Int,
             latitude: Double,
             longitude: Double,
             horizontalAccuracy: Double,
             timestamp: Date) {
            self.id = id
            self.walkID = walkID
            self.sequence = sequence
            self.segment = segment
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.timestamp = timestamp
        }
    }
}

/// The V3 shape as builds up to the walk corrections wrote it: the dog with its
/// profile fields, and a walk without `correctedAt`. Walk, link and point are
/// unchanged from V2, so V3 reuses those frozen types.
enum FrozenV3 {
    @Model
    final class DogRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var breedKind: String
        var breedLabel: String
        var ageDescription: String = ""
        var gender: String = "unspecified"
        var preferencesNote: String = ""
        @Attribute(.externalStorage) var photoData: Data?
        var createdAt: Date

        init(id: UUID = UUID(), name: String, breedKind: String, breedLabel: String = "",
             ageDescription: String = "", gender: String = "unspecified",
             preferencesNote: String = "", photoData: Data? = nil) {
            self.id = id
            self.name = name
            self.breedKind = breedKind
            self.breedLabel = breedLabel
            self.ageDescription = ageDescription
            self.gender = gender
            self.preferencesNote = preferencesNote
            self.photoData = photoData
            self.createdAt = .now
        }
    }
}

/// V1 is the first frozen shape: the journal with session fields, no track table.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [FrozenV1V2.DogRecord.self, FrozenV1V2.WalkRecord.self,
         FrozenV1V2.WalkDogRecord.self]
    }
}

/// V2 adds the private local track. Existing walks keep their data: a manual
/// walk simply has no points, which the model already represents. Frozen at the
/// shape written by builds up to the dog profile work.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [FrozenV1V2.DogRecord.self, FrozenV1V2.WalkRecord.self,
         FrozenV1V2.WalkDogRecord.self, FrozenV1V2.TrackPointRecord.self]
    }
}

/// V3 gains the dog profile fields. Frozen at the shape written by builds up to
/// the walk corrections.
enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [FrozenV3.DogRecord.self, FrozenV1V2.WalkRecord.self,
         FrozenV1V2.WalkDogRecord.self, FrozenV1V2.TrackPointRecord.self]
    }
}

/// V4: a walk gains `correctedAt`. Its four entities are still the live classes,
/// unchanged since; V5 only adds a table, so V4's identity does not move. The
/// day one of these four classes changes, freeze it here first.
enum SchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DogRecord.self, WalkRecord.self, WalkDogRecord.self, TrackPointRecord.self]
    }
}

/// V5 is the current version: it adds the chosen routine, one per dog. Existing
/// stores gain an empty table.
enum SchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DogRecord.self, WalkRecord.self, WalkDogRecord.self, TrackPointRecord.self, RoutineRecord.self]
    }
}

enum TruffloMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self),
        ]
    }
}

enum CurrentSchema {
    static let versioned = SchemaV5.self
    static var schema: Schema { Schema(versionedSchema: SchemaV5.self) }
}
