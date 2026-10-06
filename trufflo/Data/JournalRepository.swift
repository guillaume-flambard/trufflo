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
    private let container: ModelContainer

    init(context: ModelContext) {
        self.context = context
        self.container = context.container
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
            let dog = DogRecord(
                name: input.name,
                breedKind: input.breedKind,
                breedLabel: input.breedLabel,
                ageDescription: input.ageDescription,
                gender: input.gender,
                preferencesNote: input.preferencesNote,
                photoData: input.photoData
            )
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
            dog.ageDescription = input.ageDescription
            dog.gender = input.gender
            dog.preferencesNote = input.preferencesNote
            dog.photoData = input.photoData
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

    /// The walk that is still unfinished, if any. A live session is the state
    /// that makes a second start a no-op instead of a twin. An interrupted walk
    /// counts: it is not over until the user resumes, finishes or corrects it,
    /// so `startGpsSession` has to hand it back rather than open a second one.
    func liveWalk() -> WalkRecord? {
        let recording = WalkPhase.recording.rawValue
        let paused = WalkPhase.paused.rawValue
        let interrupted = WalkPhase.interrupted.rawValue
        var descriptor = FetchDescriptor<WalkRecord>(predicate: #Predicate {
            $0.phaseRaw == recording || $0.phaseRaw == paused || $0.phaseRaw == interrupted
        })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Opens one GPS session. A second call while one is live returns that walk,
    /// so a double tap cannot produce two walks in the journal.
    @discardableResult
    func startGpsSession(dogIDs: [UUID]) throws -> WalkRecord {
        if let existing = liveWalk() { return existing }
        return try commit {
            let walk = WalkRecord.gpsSession(startedAt: .now)
            context.insert(walk)
            for dogID in dogIDs {
                guard let dog = requireDog(dogID) else {
                    throw JournalError.profileMissing
                }
                context.insert(WalkDogRecord(walkID: walk.id,
                                             dogID: dog.id,
                                             dogNameSnapshot: dog.name))
            }
            return walk
        }
    }

    /// The coordinator owns the monotonic clock; this only persists what it hands over.
    func pauseWalk(_ id: UUID, confirmedSeconds: TimeInterval) throws {
        let walk = try requireLiveWalk(id, from: .recording)
        try commit {
            walk.confirmedSeconds = confirmedSeconds
            walk.phase = .paused
            walk.lastCheckpointAt = .now
            walk.revision += 1
        }
    }

    /// Resuming adds no duration on its own: the next monotonic delta is the first
    /// one counted after a pause, which is what keeps a gap from becoming time.
    func resumeWalk(_ id: UUID) throws {
        guard let walk = requireWalk(id) else { throw JournalError.walkMissing }
        guard walk.phase == .paused || walk.phase == .interrupted else {
            throw WalkError.invalidTransition
        }
        try commit {
            walk.phase = .recording
            walk.lastCheckpointAt = .now
            walk.revision += 1
        }
    }

    /// A session that ends without a normal finish keeps its confirmed duration and
    /// says so, rather than pretending the walk never ran.
    func interruptWalk(_ id: UUID, confirmedSeconds: TimeInterval) throws {
        let walk = try requireLiveWalk(id, from: nil)
        try commit {
            walk.confirmedSeconds = confirmedSeconds
            walk.phase = .interrupted
            walk.lastCheckpointAt = .now
            walk.revision += 1
        }
    }

    func checkpointWalk(_ id: UUID, confirmedSeconds: TimeInterval) throws {
        let walk = try requireLiveWalk(id, from: nil)
        try commit {
            walk.confirmedSeconds = confirmedSeconds
            walk.lastCheckpointAt = .now
            walk.revision += 1
        }
    }

    /// A session left `recording` or `paused` by a previous run cannot still be
    /// running: nothing is accruing time on a process that no longer exists. The
    /// confirmed duration is kept exactly as the last checkpoint wrote it, and the
    /// walk is presented as interrupted so the three exits can be offered.
    func recoverInterruptedSessions() throws {
        let recording = WalkPhase.recording.rawValue
        let paused = WalkPhase.paused.rawValue
        let descriptor = FetchDescriptor<WalkRecord>(predicate: #Predicate {
            $0.phaseRaw == recording || $0.phaseRaw == paused
        })
        let stale = try context.fetch(descriptor)
        guard !stale.isEmpty else { return }
        try commit {
            for walk in stale {
                walk.phase = .interrupted
                walk.revision += 1
            }
        }
    }

    private func requireLiveWalk(_ id: UUID, from expected: WalkPhase?) throws -> WalkRecord {
        guard let walk = requireWalk(id) else { throw JournalError.walkMissing }
        let isLive = walk.phase == .recording || walk.phase == .paused
        guard isLive else { throw WalkError.invalidTransition }
        if let expected, walk.phase != expected { throw WalkError.invalidTransition }
        return walk
    }

    /// Writes the note of an existing walk. Used by the post-walk summary, which
    /// is where notes belong: the live screen has no text field, so the note is
    /// written after the fact, under the same rules as a manual entry (trimmed,
    /// 500 characters at most).
    func updateWalkNote(_ id: UUID, note: String) throws {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanNote.count <= 500 else { throw WalkError.noteTooLong }
        guard let walk = requireWalk(id) else { throw JournalError.walkMissing }
        try commit {
            walk.note = cleanNote
            walk.revision += 1
        }
    }

    /// Applies a correction to a finished walk and marks it corrected (PRD F05).
    ///
    /// A recorded walk refuses a timing change: its duration and end are
    /// measured. The participants are replaced, each new one taking the dog's
    /// current name as its snapshot; a participant whose profile was deleted
    /// keeps its historical name if it stays on the walk.
    func correctWalk(_ id: UUID, with correction: WalkCorrection, at now: Date = Date()) throws {
        guard let walk = requireWalk(id), walk.phase == .completed else {
            throw JournalError.walkMissing
        }
        if walk.source != .manual && correction.touchesTiming { throw WalkError.invalidTransition }
        let current = try links(walkID: id)
        var snapshots: [UUID: String] = [:]
        for link in current { snapshots[link.dogID] = link.dogNameSnapshot }
        for dogID in correction.dogIDs where snapshots[dogID] == nil {
            guard let dog = requireDog(dogID) else { throw JournalError.profileMissing }
            snapshots[dogID] = dog.name
        }
        try commit {
            for link in current where !correction.dogIDs.contains(link.dogID) {
                context.delete(link)
            }
            let kept = Set(current.map(\.dogID))
            for dogID in correction.dogIDs where !kept.contains(dogID) {
                context.insert(WalkDogRecord(walkID: id, dogID: dogID, dogNameSnapshot: snapshots[dogID] ?? ""))
            }
            if walk.source == .manual {
                let duration = correction.durationSeconds ?? walk.confirmedSeconds
                let end = correction.endedAt ?? walk.endedAt ?? now
                walk.confirmedSeconds = duration
                walk.endedAt = end
                walk.startedAt = end.addingTimeInterval(-duration)
                walk.lastCheckpointAt = walk.startedAt
            }
            walk.note = correction.note
            walk.correctedAt = now
            walk.revision += 1
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

    // MARK: - Export

    /// Every finished walk, read back as stored, for the export (PRD F07). A walk
    /// still recording, paused or interrupted is not finished and is left out:
    /// exporting it would freeze a duration that is still moving.
    func exportWalks() throws -> [ExportWalk] {
        let finished = try context.fetch(FetchDescriptor<WalkRecord>(
            sortBy: [SortDescriptor(\.startedAt)])).filter { $0.phase == .completed }
        return try finished.map { walk in
            let names = try links(walkID: walk.id).map(\.dogNameSnapshot).sorted()
            let route = try points(walkID: walk.id)
                .sorted { $0.sequence < $1.sequence }
                .map { ExportPoint(segment: $0.segment, latitude: $0.latitude, longitude: $0.longitude,
                                   horizontalAccuracy: $0.horizontalAccuracy, timestamp: $0.timestamp) }
            return ExportWalk(id: walk.id, startedAt: walk.startedAt, endedAt: walk.endedAt,
                              durationSeconds: walk.confirmedSeconds,
                              distanceMeters: walk.recordedPathMeters,
                              source: walk.source, quality: walk.quality,
                              dogNames: names, note: walk.note, points: route)
        }
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
