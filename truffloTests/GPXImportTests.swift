import Foundation
import SwiftData
import Testing
@testable import trufflo

@Suite("GPX import")
struct GPXImportTests {
    private func gpx(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Test" xmlns="http://www.topografix.com/GPX/1/1"><trk>\(body)</trk></gpx>
        """.utf8)
    }

    @Test func aTrackGivesItsTimesSegmentsAndDistance() throws {
        let track = try GPXImport.parse(gpx("""
        <trkseg>
          <trkpt lat="48.8800000" lon="2.3800000"><time>2026-10-07T15:00:00Z</time></trkpt>
          <trkpt lat="48.8809000" lon="2.3800000"><time>2026-10-07T15:10:00Z</time></trkpt>
        </trkseg>
        <trkseg>
          <trkpt lat="48.8900000" lon="2.3800000"><time>2026-10-07T15:20:00Z</time></trkpt>
          <trkpt lat="48.8909000" lon="2.3800000"><time>2026-10-07T15:42:00.500Z</time></trkpt>
        </trkseg>
        """))
        #expect(track.points.count == 4)
        #expect(track.points.map(\.segment) == [0, 0, 1, 1])
        #expect(track.seconds == 42 * 60 + 0.5)
        // Two stretches of 0.0009° of latitude, about 100 m each; the jump between
        // the two segments (over 1 km) is a gap, not a distance.
        #expect(abs(track.meters - 200) < 2)
    }

    @Test func whatTheAppExportsItReadsBack() throws {
        let walk = ExportWalk(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_791_000_000),
                              endedAt: Date(timeIntervalSince1970: 1_791_000_600), durationSeconds: 600,
                              distanceMeters: 100, source: .gps, quality: .gpsRecorded,
                              dogNames: ["Oslo"], note: "",
                              points: [.init(segment: 0, latitude: 48.88, longitude: 2.38, horizontalAccuracy: 5,
                                             timestamp: Date(timeIntervalSince1970: 1_791_000_000)),
                                       .init(segment: 0, latitude: 48.8809, longitude: 2.38, horizontalAccuracy: 5,
                                             timestamp: Date(timeIntervalSince1970: 1_791_000_600))])
        let text = try #require(WalkExport.gpx(walk))
        let track = try GPXImport.parse(Data(text.utf8))
        #expect(track.points.count == 2)
        #expect(track.seconds == 600)
    }

    @Test func aFileWithoutTwoTimedPointsIsRefused() {
        #expect(throws: GPXImportError.tooFewPoints) {
            try GPXImport.parse(gpx("<trkseg><trkpt lat=\"48.88\" lon=\"2.38\"><time>2026-10-07T15:00:00Z</time></trkpt></trkseg>"))
        }
        #expect(throws: GPXImportError.unreadable) {
            try GPXImport.parse(Data("not xml".utf8))
        }
    }

    @Test @MainActor func anImportedTrackBecomesABaladeSuivieWithItsPoints() throws {
        let context = ModelContext(try PersistenceFactory.make(inMemory: true))
        let repository = JournalRepository(context: context)
        let dog = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
        let track = try GPXImport.parse(gpx("""
        <trkseg>
          <trkpt lat="48.8800000" lon="2.3800000"><time>2026-10-07T15:00:00Z</time></trkpt>
          <trkpt lat="48.8809000" lon="2.3800000"><time>2026-10-07T15:10:00Z</time></trkpt>
        </trkseg>
        """))
        let walk = try repository.addImportedWalk(track, dogIDs: [dog.id])
        #expect(walk.source == .gps && walk.phase == .completed)
        #expect(walk.confirmedSeconds == 600)
        #expect(abs((walk.recordedPathMeters ?? 0) - 100) < 2)
        #expect(try context.fetch(FetchDescriptor<TrackPointRecord>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<WalkDogRecord>()).count == 1)
    }
}
