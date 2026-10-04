import Foundation
import SwiftData

@MainActor
enum PersistenceFactory {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TruffloLocal",
            schema: CurrentSchema.schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: CurrentSchema.schema,
            migrationPlan: TruffloMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// A store pinned to one versioned schema, used only to build migration fixtures.
    /// The app never calls this: production always opens the current schema.
    static func makeFixtureStore<S: VersionedSchema>(
        versioned: S.Type,
        at url: URL
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: versioned)
        let configuration = ModelConfiguration(
            "TruffloFixture",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Reopens an existing on-disk store with the current schema and migration plan,
    /// so a migration can be tested against a genuinely older file.
    static func makeMigrated(at url: URL) throws -> ModelContainer {
        let schema = CurrentSchema.schema
        let configuration = ModelConfiguration(
            "TruffloFixture",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: TruffloMigrationPlan.self,
                                  configurations: [configuration])
    }
}