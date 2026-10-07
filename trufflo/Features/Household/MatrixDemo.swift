#if DEBUG
import Foundation
import SwiftData

/// `--uitesting --demo-matrix=<case>`: the seven data sets of the end-of-lot
/// capture matrix (docs/specs/A-premiere-impression.md, section 6). The
/// household case is `--demo-household`. `TRUFFLO_DEMO_PHOTO` gives the dog a
/// picture where the case has one. Never compiled into a release build.
enum MatrixDemo {
    static var requested: String? {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--demo-matrix=") }
            .map { String($0.dropFirst("--demo-matrix=".count)) }
    }

    private static var photo: Data? {
        ProcessInfo.processInfo.environment["TRUFFLO_DEMO_PHOTO"]
            .flatMap { FileManager.default.contents(atPath: $0) }
    }

    @MainActor
    static func seed(_ name: String, in context: ModelContext) throws {
        let repository = JournalRepository(context: context)
        let now = Date()
        switch name {
        case "fresh":
            break
        case "first-dog":
            try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
        case "normal":
            let oslo = try repository.addDog(try DogInput(name: "Oslo", breedKind: "mixed", photoData: photo))
            try manual(repository, oslo, minutes: 35, note: "Tour du parc", endedAt: now.addingTimeInterval(-26 * 3600))
            try manual(repository, oslo, minutes: 20, note: "", endedAt: now.addingTimeInterval(-3 * 3600))
            try gps(context, oslo, minutes: 42, meters: 2140, endedAt: now.addingTimeInterval(-50 * 3600))
            try gps(context, oslo, minutes: 28, meters: 1480, endedAt: now.addingTimeInterval(-74 * 3600))
        case "long-name":
            let pepite = try repository.addDog(try DogInput(name: "Pépite de la Vallée Verte", breedKind: "unknown", photoData: photo))
            try manual(repository, pepite, minutes: 30, note: "", endedAt: now.addingTimeInterval(-4 * 3600))
        case "multi":
            let oslo = try repository.addDog(try DogInput(name: "Oslo", breedKind: "mixed", photoData: photo))
            let pixel = try repository.addDog(try DogInput(name: "Pixel", breedKind: "unknown"))
            try repository.addDog(try DogInput(name: "Nougat", breedKind: "unknown"))
            try manual(repository, oslo, minutes: 35, note: "", endedAt: now.addingTimeInterval(-26 * 3600))
            try manual(repository, pixel, minutes: 20, note: "", endedAt: now.addingTimeInterval(-3 * 3600))
        default:
            throw MatrixError.unknownCase(name)
        }
        try context.save()
    }

    enum MatrixError: Error { case unknownCase(String) }

    @MainActor
    private static func manual(_ repository: JournalRepository, _ dog: DogRecord,
                               minutes: Int, note: String, endedAt: Date) throws {
        try repository.addManualWalk(
            try ManualWalkInput(dogIDs: [dog.id], durationSeconds: TimeInterval(minutes * 60), note: note),
            endedAt: endedAt)
    }

    @MainActor
    private static func gps(_ context: ModelContext, _ dog: DogRecord,
                            minutes: Int, meters: Double, endedAt: Date) throws {
        let seconds = TimeInterval(minutes * 60)
        let walk = WalkRecord(startedAt: endedAt.addingTimeInterval(-seconds), endedAt: endedAt,
                              confirmedSeconds: seconds, phase: .completed,
                              source: .gps, quality: .gpsRecorded)
        walk.recordedPathMeters = meters
        context.insert(walk)
        context.insert(WalkDogRecord(walkID: walk.id, dogID: dog.id, dogNameSnapshot: dog.name))
    }
}
#endif
