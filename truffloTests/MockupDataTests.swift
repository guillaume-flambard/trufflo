import Foundation
import SwiftData
import Testing
@testable import trufflo

/// The data the 2026-10-07 mock-ups show (chantier 8): dog size, weight and
/// traits, walk title, mood, place, weather and photos, and the calorie estimate.
@Suite("Mock-up data")
@MainActor
struct MockupDataTests {
    private func repository() throws -> (JournalRepository, ModelContext) {
        let context = ModelContext(try PersistenceFactory.make(inMemory: true))
        return (JournalRepository(context: context), context)
    }

    @Test func aDogKeepsItsDeclaredSizeWeightAndTraits() throws {
        let (repo, _) = try repository()
        let dog = try repo.addDog(try DogInput(name: "Oslo", breedKind: "mixed", size: .medium,
                                               weightKg: 18, traits: [.sociable, .playful]))
        #expect(dog.size == .medium)
        #expect(dog.weightKg == 18)
        #expect(dog.traits == [.sociable, .playful])
    }

    @Test func anImplausibleWeightIsRefused() {
        #expect(throws: DogError.invalidWeight) {
            try DogInput(name: "Oslo", breedKind: "unknown", weightKg: 0)
        }
        #expect(throws: DogError.invalidWeight) {
            try DogInput(name: "Oslo", breedKind: "unknown", weightKg: 200)
        }
    }

    @Test func aWalkKeepsItsTitleMoodAndNote() throws {
        let (repo, _) = try repository()
        let dog = try repo.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
        let walk = try repo.addManualWalk(try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 2100, note: ""),
                                          endedAt: .now)
        try repo.updateWalkDetails(walk.id, title: "  Tour du parc ", mood: .calm, note: "Matin calme")
        #expect(walk.title == "Tour du parc")
        #expect(walk.mood == .calm)
        #expect(walk.note == "Matin calme")
    }

    @Test func aTooLongTitleIsRefused() throws {
        let (repo, _) = try repository()
        let dog = try repo.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
        let walk = try repo.addManualWalk(try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 600, note: ""), endedAt: .now)
        #expect(throws: WalkError.titleTooLong) {
            try repo.updateWalkDetails(walk.id, title: String(repeating: "a", count: 81), mood: nil, note: "")
        }
    }

    @Test func photosFollowTheirWalkAndLeaveWithIt() throws {
        let (repo, context) = try repository()
        let dog = try repo.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
        let walk = try repo.addManualWalk(try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 600, note: ""), endedAt: .now)
        try repo.addWalkPhoto(walk.id, data: Data([1, 2, 3]))
        try repo.addWalkPhoto(walk.id, data: Data([4, 5]))
        #expect(try context.fetch(FetchDescriptor<WalkPhotoRecord>()).count == 2)
        try repo.deleteWalk(walk.id)
        #expect(try context.fetch(FetchDescriptor<WalkPhotoRecord>()).isEmpty)
    }

    @Test func globalErasureTakesThePhotosToo() throws {
        let (repo, context) = try repository()
        let dog = try repo.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
        let walk = try repo.addManualWalk(try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 600, note: ""), endedAt: .now)
        try repo.addWalkPhoto(walk.id, data: Data([1]))
        try repo.eraseAll()
        #expect(try context.fetch(FetchDescriptor<WalkPhotoRecord>()).isEmpty)
    }

    /// 0.6 kcal/kg/km for a long-legged dog, 1.3 for a short-legged one, the
    /// middle when the size is not given.
    @Test func caloriesAreAnEstimateFromWeightDistanceAndSize() {
        #expect(CalorieEstimate.kcal(weightKg: 20, meters: 2000, size: .large) == 24)
        #expect(CalorieEstimate.kcal(weightKg: 8, meters: 1500, size: .small) == 16)
        #expect(CalorieEstimate.kcal(weightKg: 18, meters: 2140, size: nil) == 37)
        #expect(CalorieEstimate.kcal(weightKg: nil, meters: 2000, size: .medium) == nil)
        #expect(CalorieEstimate.kcal(weightKg: 18, meters: nil, size: .medium) == nil)
    }

    @Test func aNewPlanReplacesThePreviousOneAndErasureTakesIt() throws {
        let (repo, context) = try repository()
        try repo.planWalk(at: .now.addingTimeInterval(3600), placeName: "Parc", latitude: 48.88, longitude: 2.38)
        try repo.planWalk(at: .now.addingTimeInterval(7200), placeName: " Buttes-Chaumont ", latitude: nil, longitude: nil)
        let plans = try context.fetch(FetchDescriptor<PlannedWalkRecord>())
        #expect(plans.count == 1)
        #expect(plans[0].placeName == "Buttes-Chaumont")
        try repo.eraseAll()
        #expect(try context.fetch(FetchDescriptor<PlannedWalkRecord>()).isEmpty)
    }
}
