import Foundation
import SwiftData
import Testing
@testable import trufflo

// MARK: - Format, pure domain

private let start = Date(timeIntervalSince1970: 1_791_000_000)

private func gpsWalk(points: [ExportPoint], note: String = "") -> ExportWalk {
    ExportWalk(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(1800),
               durationSeconds: 1800, distanceMeters: 2140, source: .gps, quality: .gpsRecorded,
               dogNames: ["Oslo"], note: note, points: points)
}

private func manualWalk(note: String = "") -> ExportWalk {
    ExportWalk(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(2520),
               durationSeconds: 2520, distanceMeters: nil, source: .manual, quality: .manual,
               dogNames: ["Oslo", "Mirabelle"], note: note, points: [])
}

private func point(_ segment: Int, _ lat: Double, _ seconds: Double) -> ExportPoint {
    ExportPoint(segment: segment, latitude: lat, longitude: 2.3522,
                horizontalAccuracy: 6, timestamp: start.addingTimeInterval(seconds))
}

@Test func anUnmeasuredDistanceIsAnEmptyCellNeverZero() {
    let csv = WalkExport.csv([manualWalk()])
    let row = csv.split(separator: "\r\n").map(String.init)[1]
    let cells = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    #expect(cells[3] == "2520")
    #expect(cells[4] == "", "une distance non mesurée ne doit pas s'écrire 0")
    #expect(cells[9] == "", "une balade manuelle n'a pas de fichier de tracé")
}

@Test func csvQuotesFieldsThatWouldBreakTheColumns() {
    let csv = WalkExport.csv([manualWalk(note: "Parc, puis \"canal\"\nretour")])
    #expect(csv.contains("\"Parc, puis \"\"canal\"\"\nretour\""))
    #expect(csv.hasPrefix(WalkExport.csvHeader.joined(separator: ",") + "\r\n"))
}

@Test func csvListsWalksOldestFirstWithIsoDates() {
    let later = ExportWalk(id: UUID(), startedAt: start.addingTimeInterval(86_400), endedAt: nil,
                           durationSeconds: 60, distanceMeters: nil, source: .manual, quality: .manual,
                           dogNames: [], note: "", points: [])
    let rows = WalkExport.csv([later, manualWalk()]).split(separator: "\r\n")
    #expect(rows.count == 3)
    #expect(rows[1].contains(start.formatted(.iso8601)))
}

@Test func aManualWalkNeverGetsAFabricatedRoute() {
    #expect(WalkExport.gpx(manualWalk()) == nil)
    // A GPS walk that kept a single point has no route to draw either.
    #expect(WalkExport.gpx(gpsWalk(points: [point(1, 48.8566, 0)])) == nil)
}

@Test func gpxKeepsEachRecordedSegmentApart() throws {
    let walk = gpsWalk(points: [point(1, 48.8566, 0), point(1, 48.8570, 30),
                                point(2, 48.8580, 400), point(2, 48.8585, 430)])
    let gpx = try #require(WalkExport.gpx(walk))
    #expect(gpx.components(separatedBy: "<trkseg>").count - 1 == 2,
            "une pause doit couper le tracé, pas le relier en ligne droite")
    #expect(gpx.components(separatedBy: "<trkpt ").count - 1 == 4)
    #expect(gpx.contains("lat=\"48.8566000\""))
    #expect(gpx.contains("<name>Balade avec Oslo</name>"))
    #expect(gpx.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
}

@Test func gpxEscapesNamesThatWouldBreakTheXml() throws {
    var walk = gpsWalk(points: [point(1, 48.8566, 0), point(1, 48.8570, 30)])
    walk = ExportWalk(id: walk.id, startedAt: walk.startedAt, endedAt: walk.endedAt,
                      durationSeconds: walk.durationSeconds, distanceMeters: walk.distanceMeters,
                      source: .gps, quality: .gpsRecorded, dogNames: ["Tom & <Jerry>"],
                      note: "", points: walk.points)
    let gpx = try #require(WalkExport.gpx(walk))
    #expect(gpx.contains("Tom &amp; &lt;Jerry&gt;"))
}

// MARK: - Storage and archive

@MainActor
@Test func exportReadsOnlyFinishedWalksWithTheirRouteInOrder() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let repository = JournalRepository(context: context)
    let dog = try repository.addDog(try DogInput(name: "Oslo", breedKind: "unknown"))
    try repository.addManualWalk(try ManualWalkInput(dogIDs: [dog.id], durationSeconds: 900),
                                 endedAt: .now)

    let gps = WalkRecord(startedAt: start, endedAt: start.addingTimeInterval(600),
                         confirmedSeconds: 600, phase: .completed, source: .gps, quality: .gpsRecorded)
    gps.recordedPathMeters = 410
    context.insert(gps)
    context.insert(WalkDogRecord(walkID: gps.id, dogID: dog.id, dogNameSnapshot: "Oslo"))
    // Inserted out of order: the export must follow the recorded sequence.
    for (sequence, lat) in [(2, 48.8580), (0, 48.8566), (1, 48.8572)] {
        context.insert(TrackPointRecord(walkID: gps.id, sequence: sequence, segment: 1,
                                        latitude: lat, longitude: 2.3522, horizontalAccuracy: 5,
                                        timestamp: start.addingTimeInterval(Double(sequence) * 60)))
    }
    let live = WalkRecord(startedAt: .now, phase: .recording, source: .gps)
    context.insert(live)
    try context.save()

    let exported = try repository.exportWalks()
    #expect(exported.count == 2, "une balade en cours ne fait pas partie de l'export")
    let route = try #require(exported.first { $0.id == gps.id })
    #expect(route.points.map(\.latitude) == [48.8566, 48.8572, 48.8580])
    #expect(route.distanceMeters == 410)
    #expect(route.dogNames == ["Oslo"])
    let manual = try #require(exported.first { $0.source == .manual })
    #expect(manual.distanceMeters == nil)
    #expect(manual.points.isEmpty)
}

@Test func archiveIsOneZipAndRefusesAnEmptyJournal() throws {
    #expect(throws: ExportArchive.Failure.nothingToExport) {
        try ExportArchive.make(from: [])
    }
    let walk = gpsWalk(points: [point(1, 48.8566, 0), point(1, 48.8570, 30)])
    let url = try ExportArchive.make(from: [walk, manualWalk()])
    #expect(url.pathExtension == "zip")
    let data = try Data(contentsOf: url)
    #expect(data.prefix(2) == Data([0x50, 0x4B]), "l'archive doit être un zip")
    #expect(data.count > 200)
}

@Test func theExportCarriesTitleMoodPlaceWeatherAndPhotosAtTheEnd() {
    let walk = ExportWalk(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(1800),
                          durationSeconds: 1800, distanceMeters: nil, source: .manual, quality: .manual,
                          dogNames: ["Oslo"], note: "", points: [],
                          title: "Tour du parc", mood: .calm, placeName: "Parc", weather: .sunny,
                          temperatureC: 18, photoCount: 2)
    let rows = WalkExport.csv([walk]).split(separator: "\r\n").map(String.init)
    #expect(rows[0].hasPrefix("id,debut,fin,duree_secondes,distance_metres,origine,qualite,chiens,note,fichier_trace,"))
    let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    #expect(Array(cells.suffix(6)) == ["Tour du parc", "Balade tranquille", "Parc", "Ensoleillé", "18", "2"])
}
