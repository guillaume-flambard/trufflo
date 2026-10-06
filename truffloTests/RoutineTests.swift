import Foundation
import SwiftData
import Testing
@testable import trufflo

@Test func aRoutineNeedsAtLeastOneReferencePointWithinSaneBounds() {
    #expect(throws: DogRoutine.Invalid.empty) {
        try DogRoutine(outingsPerDay: nil, minutesPerOuting: nil, slots: [])
    }
    #expect(throws: DogRoutine.Invalid.outOfRange) {
        try DogRoutine(outingsPerDay: 0, minutesPerOuting: nil, slots: [])
    }
    #expect(throws: DogRoutine.Invalid.outOfRange) {
        try DogRoutine(outingsPerDay: nil, minutesPerOuting: 600, slots: [])
    }
    #expect((try? DogRoutine(outingsPerDay: nil, minutesPerOuting: nil, slots: [.morning])) != nil)
}

@Test func theRoutineReadsAsChosenNotAsATarget() throws {
    let routine = try DogRoutine(outingsPerDay: 2, minutesPerOuting: 30, slots: [.evening, .morning])
    #expect(routine.summary == "2 sorties par jour, environ 30 min, matin et soir")
    // Today is said as a fact, whatever the count: never a shortfall.
    for count in 0...4 {
        let line = routine.today(recordedOutings: count).lowercased()
        for word in ["manque", "reste", "objectif", "retard", "encore", "rattrap"] {
            #expect(!line.contains(word), "« \(line) » sonne comme un reproche")
        }
    }
    #expect(routine.today(recordedOutings: 1) == "Aujourd'hui, 1 sortie enregistrée.")
    #expect(routine.today(recordedOutings: 0) == "Aujourd'hui, aucune sortie enregistrée pour l'instant.")
}

@MainActor
@Test func pausingTheRoutineLeavesTheHistoryUntouched() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    let dog = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    try repository.addManualWalk(try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 1800, note: "Parc"),
                                 endedAt: .now)
    try repository.saveRoutine(try DogRoutine(outingsPerDay: 2, minutesPerOuting: nil, slots: []), for: dog.id)

    let before = try ModelContext(container).fetch(FetchDescriptor<WalkRecord>())
        .map { "\($0.confirmedSeconds)-\($0.revision)-\($0.note)" }
    try repository.setRoutinePaused(true, for: dog.id)
    try repository.setRoutinePaused(false, for: dog.id)
    let after = try ModelContext(container).fetch(FetchDescriptor<WalkRecord>())
        .map { "\($0.confirmedSeconds)-\($0.revision)-\($0.note)" }
    #expect(before == after, "suspendre une routine ne doit pas toucher l'historique")

    try repository.setRoutinePaused(true, for: dog.id)
    let stored = try #require(try repository.routine(for: dog.id))
    #expect(stored.isPaused)
    #expect(stored.routine?.outingsPerDay == 2, "en pause, la routine est gardée, pas oubliée")
}

@MainActor
@Test func savingAgainReplacesTheRoutineAndKeepsItsPause() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    let dog = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    try repository.saveRoutine(try DogRoutine(outingsPerDay: 2, minutesPerOuting: nil, slots: []), for: dog.id)
    try repository.setRoutinePaused(true, for: dog.id)
    try repository.saveRoutine(try DogRoutine(outingsPerDay: nil, minutesPerOuting: 45, slots: [.midday]), for: dog.id)

    let all = try ModelContext(container).fetch(FetchDescriptor<RoutineRecord>())
    #expect(all.count == 1, "une seule routine par chien")
    #expect(all[0].routine?.outingsPerDay == nil)
    #expect(all[0].routine?.minutesPerOuting == 45)
    #expect(all[0].routine?.slots == [.midday])
    #expect(all[0].isPaused)
}

@MainActor
@Test func theRoutineGoesWithItsDogAndWithTheGlobalErasure() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    let oslo = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    let mira = try repository.addDog(try DogInput(name: "Mirabelle", breedKind: "unknown"))
    let routine = try DogRoutine(outingsPerDay: 1, minutesPerOuting: nil, slots: [])
    try repository.saveRoutine(routine, for: oslo.id)
    try repository.saveRoutine(routine, for: mira.id)

    try repository.deleteDog(oslo.id)
    #expect(try repository.routine(for: oslo.id) == nil)
    #expect(try repository.routine(for: mira.id) != nil)

    try repository.eraseAll()
    #expect(try ModelContext(container).fetch(FetchDescriptor<RoutineRecord>()).isEmpty)
}

@MainActor
@Test func aRoutineCannotBeSavedForAMissingDog() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let repository = JournalRepository(context: container.mainContext)
    #expect(throws: JournalError.profileMissing) {
        try repository.saveRoutine(try DogRoutine(outingsPerDay: 1, minutesPerOuting: nil, slots: []), for: UUID())
    }
}
