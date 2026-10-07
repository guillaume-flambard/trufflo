import Foundation
import Testing
@testable import trufflo

@Test func theWalkSummaryCarriesTitleMoodAndWeatherButNoPlace() throws {
    let summary = WalkSummaryDTO(id: UUID(), householdID: UUID(), source: "gps", quality: "gpsRecorded",
                                 startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1800),
                                 confirmedSeconds: 1800, recordedPathMeters: 2140, correctedAt: nil,
                                 title: "Balade dans le quartier", mood: "great", weather: "sunny", temperatureC: 18)
    let json = try #require(try JSONSerialization.jsonObject(with: HouseholdCoding.encoder().encode(summary)) as? [String: Any])
    #expect(json["title"] as? String == "Balade dans le quartier")
    #expect(json["mood"] as? String == "great")
    #expect(json["weather"] as? String == "sunny")
    #expect(json["temperature_c"] as? Double == 18)
    #expect(json["place_name"] == nil)
    // A cleared mood goes up as an explicit null, so the server clears it too.
    let cleared = WalkSummaryDTO(id: UUID(), householdID: UUID(), source: "manual", quality: "manual",
                                 startedAt: .now, endedAt: .now, confirmedSeconds: 60, recordedPathMeters: nil,
                                 correctedAt: nil)
    let clearedJSON = try #require(try JSONSerialization.jsonObject(with: HouseholdCoding.encoder().encode(cleared)) as? [String: Any])
    #expect(clearedJSON["mood"] is NSNull)
}

@Test func theDogCarriesSizeWeightAndTraitsButNoSex() throws {
    let dog = DogDTO(id: UUID(), householdID: UUID(), name: "Oslo", breedKind: "mixed", breedLabel: "",
                     ageDescription: "3 ans", size: "medium", weightKg: 18, traits: ["sociable"])
    let json = try #require(try JSONSerialization.jsonObject(with: HouseholdCoding.encoder().encode(dog)) as? [String: Any])
    #expect(json["size"] as? String == "medium")
    #expect(json["weight_kg"] as? Double == 18)
    #expect(json["traits"] as? [String] == ["sociable"])
    #expect(json["gender"] == nil)
}

@Test func aWalkFromAServerWithoutTheDetailsColumnsStillDecodes() throws {
    let body = """
    {"id":"33333333-3333-3333-3333-333333333333","author_id":"00000000-0000-0000-0000-00000000000a",
     "revision":1,"source":"gps","quality":"gpsRecorded","started_at":"2026-10-07T15:00:00.000Z",
     "ended_at":"2026-10-07T15:42:00.000Z","confirmed_seconds":2520,"recorded_path_meters":2140,
     "corrected_at":null,"updated_at":"2026-10-07T15:42:01.000Z","deleted_at":null,"walk_dogs":[]}
    """
    let walk = try HouseholdCoding.decoder().decode(RemoteWalkDTO.self, from: Data(body.utf8))
    #expect(walk.title.isEmpty)
    #expect(walk.mood == nil)
    #expect(walk.weather == nil)
}
