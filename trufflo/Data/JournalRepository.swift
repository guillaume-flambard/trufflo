import Foundation
import SwiftData

enum JournalError: Error, Equatable {
    case profileMissing
    case walkMissing
    case persistence
}

/// The only place that mutates the journal.
///
/// Views read with `@Query` and write through this type, so a transaction can
/// never be left half applied by a loop sitting in a SwiftUI body. Every command
/// either commits or rolls back to the last saved state.
///
/// Referential integrity is the repository's job, not SwiftData's: links and
/// track points carry their own `walkID`/`dogID` with no foreign key.
@MainActor
struct JournalRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Reading

    func dog(id: UUID) -> DogRecord? {
        var descriptor = FetchDescriptor<DogRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func walk(id: UUID) -> WalkRecord? {
        var descriptor = FetchDescriptor<WalkRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Participants of one walk, in journal order. Used by the detail screen.
    func participants(walkID: UUID) -> [WalkDogRecord] {
        let descriptor = FetchDescriptor<WalkDogRecord>(predicate: #Predicate { $0.walkID == walkID })
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Profiles

    @discardableResult
    func addDog(_ input: DogInput) throws -> DogRecord {
        try commit {
            let dog = DogRecord(name: input.name,
                                breedKind: input.breedKind,
                                breedLabel: input.breedLabel)
            context.insert(dog)
            return dog
        }
    }

    /// Changes the profile only. Existing links keep the name they recorded, so
    /// renaming a dog never rewrites history already shown in the journal.
    func updateDog(_ id: UUID, with input: DogInput) throws {
        try commit {
            guard let dog = requireDog(id) else { throw JournalError.profileMissing }
            dog.name = input.name
            dog.breedKind = input.breedKind
            dog.breedLabel = input.breedLabel
        }
    }

    /// Deletes the profile and nothing else. `WalkDogRecord.dogNameSnapshot`
    /// keeps naming past walks, which is why the column exists.
    func deleteDog(_ id: UUID) throws {
        try commit {
            guard let dog = requireDog(id) else { throw JournalError.profileMissing }
            context.delete(dog)
        }
    }

    // MARK: - Walks

    @discardableResult
    func addManualWalk(_ input: ManualWalkInput, endedAt: Date) throws -> WalkRecord {
        try commit {
            let walk = WalkRecord.manual(endedAt: endedAt,
                                         durationSeconds: input.durationSeconds,
                                         note: input.note)
            context.insert(walk)
            for dogID in input.dogIDs {
                guard let dog = requireDog(dogID) else {
                    // A profile vanished between form and save: refuse the whole
                    // walk rather than record a participation naming nobody.
                    throw JournalError.profileMissing
                }
                context.insert(WalkDogRecord(walkID: walk.id,
                                             dogID: dog.id,
                                             dogNameSnapshot: dog.name))
            }
            return walk
        }
    }

    /// Removes the walk, its participations and its recorded points in one
    /// transaction. Nothing is left behind pointing at a walk that no longer exists.
    func deleteWalk(_ id: UUID) throws {
        try commit {
            guard let walk = requireWalk(id) else { throw JournalError.walkMissing }
            for link in try links(walkID: id) { context.delete(link) }
            for point in try points(walkID: id) { context.delete(point) }
            context.delete(walk)
        }
    }

    // MARK: - Global erasure

    /// Everything, points included. The previous implementation missed track
    /// points, which was invisible only because no walk had any yet.
    func eraseAll() throws {
        try commit {
            for point in try all(TrackPointRecord.self) { context.delete(point) }
            for link in try all(WalkDogRecord.self) { context.delete(link) }
            for walk in try all(WalkRecord.self) { context.delete(walk) }
            for dog in try all(DogRecord.self) { context.delete(dog) }
        }
    }

    // MARK: - Plumbing

    private func commit<T>(_ work: () throws -> T) throws -> T {
        do {
            let value = try work()
            try context.save()
            return value
        } catch let error as JournalError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw JournalError.persistence
        }
    }

    private func requireDog(_ id: UUID) -> DogRecord? {
        dog(id: id)
    }

    private func requireWalk(_ id: UUID) -> WalkRecord? {
        walk(id: id)
    }

    private func links(walkID: UUID) throws -> [WalkDogRecord] {
        try context.fetch(FetchDescriptor<WalkDogRecord>(
            predicate: #Predicate { $0.walkID == walkID }))
    }

    private func points(walkID: UUID) throws -> [TrackPointRecord] {
        try context.fetch(FetchDescriptor<TrackPointRecord>(
            predicate: #Predicate { $0.walkID == walkID }))
    }

    private func all<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }
}
