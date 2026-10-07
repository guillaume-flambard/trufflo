#if DEBUG
import Foundation
import SwiftData

/// `--uitesting --demo-mockup`: the data of the 2026-10-07 mock-ups, so a capture
/// of the app can be laid over a mock-up and compared (chantier 8, M08). Oslo,
/// a balade in the Buttes-Chaumont, the others' balades in the foyer.
/// `TRUFFLO_DEMO_PHOTO` gives Oslo and the walk photos their picture. Never
/// compiled into a release build.
enum MockupDemo {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("--demo-mockup") }

    @MainActor
    static func seed(_ context: ModelContext) throws {
        let photo = ProcessInfo.processInfo.environment["TRUFFLO_DEMO_PHOTO"]
            .flatMap { FileManager.default.contents(atPath: $0) }
        let repository = JournalRepository(context: context)
        let calendar = Calendar.current
        func today(_ hour: Int, _ minute: Int, daysAgo: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        let oslo = try repository.addDog(try DogInput(
            name: "Oslo", breedKind: "mixed", ageDescription: "3 ans", gender: "male",
            photoData: photo, size: .medium, weightKg: 18, traits: [.sociable]))

        // Today 17:48, the Buttes-Chaumont, as on every mock-up.
        let quartier = gps(context, oslo, minutes: 42, meters: 2140, endedAt: today(17, 48),
                           from: (48.8822, 2.3792), to: (48.8790, 2.3845))
        try repository.updateWalkDetails(quartier.id, title: "Balade dans le quartier", mood: .great,
                                         note: "Il a croisé le beagle de la rue du Parc.\nUne super balade dans la bonne humeur !")
        try repository.setWalkSurroundings(quartier.id, placeName: "Parc des Buttes-Chaumont, Paris 19e",
                                           weather: .sunny, temperatureC: 18)
        // Five photos, on its page; its card shows the tracé, which comes first.
        if let photo { for _ in 0..<5 { try repository.addWalkPhoto(quartier.id, data: photo) } }


        // Yesterday 08:15: recorded, 1,87 km measured, but no tracé kept (a
        // partial measure), so its card shows its photo, as in the mock-up.
        let parc = WalkRecord(startedAt: today(7, 40, daysAgo: 1), endedAt: today(8, 15, daysAgo: 1),
                              confirmedSeconds: 35 * 60, phase: .completed, source: .gps, quality: .gpsPartial)
        parc.recordedPathMeters = 1870
        context.insert(parc)
        context.insert(WalkDogRecord(walkID: parc.id, dogID: oslo.id, dogNameSnapshot: oslo.name))
        try repository.updateWalkDetails(parc.id, title: "Tour du parc", mood: .calm, note: "Matin calme et ensoleillé ☀️")
        if let photo { try repository.addWalkPhoto(parc.id, data: photo) }
        // Every demo photo was added yesterday at 17:48, as the foyer's activity says.
        for added in try context.fetch(FetchDescriptor<WalkPhotoRecord>()) {
            added.createdAt = today(17, 48, daysAgo: 1)
        }

        // Two days before, along the river.
        let riviere = gps(context, oslo, minutes: 52, meters: 3400, endedAt: today(16, 2, daysAgo: 3),
                          from: (48.8838, 2.3700), to: (48.8800, 2.3765))
        try repository.updateWalkDetails(riviere.id, title: "Bords de rivière", mood: .discovery, note: "")

        // The foyer: Vous, Natha and Camille.
        let me = UUID(), natha = UUID(), camille = UUID()
        let household = HouseholdRecord(id: UUID(), name: "Maison", myUserID: me, myRole: .owner,
                                        myDisplayName: "Guillaume", joinedAt: .now.addingTimeInterval(-30 * 86400))
        household.lastSyncAt = .now.addingTimeInterval(-300)
        context.insert(household)
        context.insert(HouseholdMemberRecord(userID: me, displayName: "Guillaume", role: .owner))
        context.insert(HouseholdMemberRecord(userID: natha, displayName: "Natha", role: .contributor))
        context.insert(HouseholdMemberRecord(userID: camille, displayName: "Camille", role: .contributor))
        context.insert(DogLinkRecord(localDogID: oslo.id, remoteDogID: oslo.id))
        context.insert(SharedWalkRecord(RemoteWalkDTO(
            id: UUID(), authorID: camille, revision: 1, source: "gps", quality: "gpsRecorded",
            startedAt: today(7, 37), endedAt: today(8, 15), confirmedSeconds: 38 * 60, recordedPathMeters: 2100,
            correctedAt: nil, updatedAt: .now, deletedAt: nil, dogs: [.init(dogID: oslo.id, dogNameSnapshot: "Oslo")])))
        context.insert(SharedWalkRecord(RemoteWalkDTO(
            id: UUID(), authorID: natha, revision: 1, source: "gps", quality: "gpsRecorded",
            startedAt: today(15, 10, daysAgo: 3), endedAt: today(16, 2, daysAgo: 3), confirmedSeconds: 52 * 60,
            recordedPathMeters: 3400, correctedAt: nil, updatedAt: .now, deletedAt: nil,
            dogs: [.init(dogID: oslo.id, dogNameSnapshot: "Oslo")])))
        try context.save()
    }

    /// A balade suivie along a gentle curve between two points, as recorded.
    @MainActor
    private static func gps(_ context: ModelContext, _ dog: DogRecord, minutes: Int, meters: Double,
                            endedAt: Date, from: (Double, Double), to: (Double, Double)) -> WalkRecord {
        let seconds = TimeInterval(minutes * 60)
        let started = endedAt.addingTimeInterval(-seconds)
        let walk = WalkRecord(startedAt: started, endedAt: endedAt, confirmedSeconds: seconds,
                              phase: .completed, source: .gps, quality: .gpsRecorded)
        walk.recordedPathMeters = meters
        context.insert(walk)
        context.insert(WalkDogRecord(walkID: walk.id, dogID: dog.id, dogNameSnapshot: dog.name))
        let count = 90
        for index in 0..<count {
            let t = Double(index) / Double(count - 1)
            // East first, then a long bend south-east: the shape of the mock-up's route.
            let latitude = from.0 + (to.0 - from.0) * (t * t) + 0.0008 * sin(t * .pi)
            let longitude = from.1 + (to.1 - from.1) * sqrt(t)
            context.insert(TrackPointRecord(walkID: walk.id, sequence: index, segment: 0,
                                            latitude: latitude, longitude: longitude, horizontalAccuracy: 6,
                                            timestamp: started.addingTimeInterval(seconds * t)))
        }
        walk.trackSegmentCount = 1
        walk.measuredEdgeCount = count - 1
        return walk
    }
}
#endif
