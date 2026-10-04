import Foundation
import SwiftData

/// V1 is the first frozen shape. It already carries the session fields because no
/// Trufflo data has ever left a developer machine: the M0 shape was explicitly
/// experimental and is not treated as a released schema.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DogRecord.self, WalkRecord.self, WalkDogRecord.self]
    }
}

/// V2 adds the private local track. Existing walks keep their data: a manual walk
/// simply has no points, which the model already represents.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DogRecord.self, WalkRecord.self, WalkDogRecord.self, TrackPointRecord.self]
    }
}

enum TruffloMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

enum CurrentSchema {
    static let versioned = SchemaV2.self
    static var schema: Schema { Schema(versionedSchema: SchemaV2.self) }
}