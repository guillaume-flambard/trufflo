#if DEBUG
import Foundation
import SwiftData

/// `--uitesting --demo-household`: an in-memory journal already sharing a
/// household with one other member, for screenshots and UI checks of the
/// shared journal without a server. Never compiled into a release build.
enum HouseholdDemo {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("--demo-household") }
    static var dogsOnly: Bool { ProcessInfo.processInfo.arguments.contains("--demo-dogs-only") }

    /// Two dogs and no household: the states before joining one.
    @MainActor
    static func seedDogs(_ context: ModelContext) throws {
        let repository = JournalRepository(context: context)
        try repository.addDog(try DogInput(name: "Oslo", breedKind: "mixed"))
        try repository.addDog(try DogInput(name: "Pixel", breedKind: "unknown"))
    }

    @MainActor
    static func seed(_ context: ModelContext) throws {
        let me = UUID()
        let bruno = UUID()
        let repository = JournalRepository(context: context)
        let oslo = try repository.addDog(try DogInput(name: "Oslo", breedKind: "mixed"))
        let now = Date()
        try repository.addManualWalk(try ManualWalkInput(dogIDs: [oslo.id], durationSeconds: 35 * 60, note: "Tour du parc"),
                                     endedAt: now.addingTimeInterval(-26 * 3600))
        try repository.addManualWalk(try ManualWalkInput(dogIDs: [oslo.id], durationSeconds: 20 * 60, note: ""),
                                     endedAt: now.addingTimeInterval(-3 * 3600))

        let household = HouseholdRecord(id: UUID(), name: "Maison", myUserID: me, myRole: .owner,
                                        myDisplayName: "Guillaume", joinedAt: now.addingTimeInterval(-7 * 86400))
        household.lastSyncAt = now.addingTimeInterval(-300)
        context.insert(household)
        context.insert(HouseholdMemberRecord(userID: me, displayName: "Guillaume", role: .owner))
        context.insert(HouseholdMemberRecord(userID: bruno, displayName: "Bruno", role: .contributor))
        context.insert(DogLinkRecord(localDogID: oslo.id, remoteDogID: oslo.id))

        // Bruno walked Oslo this morning with GPS, and overlapped one of mine.
        context.insert(SharedWalkRecord(RemoteWalkDTO(
            id: UUID(), authorID: bruno, revision: 1, source: "gps", quality: "gpsRecorded",
            startedAt: now.addingTimeInterval(-5 * 3600), endedAt: now.addingTimeInterval(-5 * 3600 + 2400),
            confirmedSeconds: 2400, recordedPathMeters: 2140, correctedAt: nil, updatedAt: now, deletedAt: nil,
            dogs: [.init(dogID: oslo.id, dogNameSnapshot: "Oslo")])))
        context.insert(SharedWalkRecord(RemoteWalkDTO(
            id: UUID(), authorID: bruno, revision: 2, source: "manual", quality: "manual",
            startedAt: now.addingTimeInterval(-3 * 3600 - 900), endedAt: now.addingTimeInterval(-3 * 3600 + 300),
            confirmedSeconds: 1200, recordedPathMeters: nil, correctedAt: now.addingTimeInterval(-3600),
            updatedAt: now, deletedAt: nil,
            dogs: [.init(dogID: oslo.id, dogNameSnapshot: "Oslo")])))
        try context.save()
    }
}
#endif
