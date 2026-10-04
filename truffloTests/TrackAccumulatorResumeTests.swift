import Foundation
import SwiftData
import Testing
@testable import trufflo

@MainActor
@Test func domainAccumulatorResumesFromPersistedState() throws {
    let head = LocationFix(latitude: 48.85, longitude: 2.351, horizontalAccuracy: 5,
                           timestamp: Date(timeIntervalSince1970: 1_010))
    var resumed = TrackAccumulator(restoredDistanceMeters: 68, measuredEdgeCount: 1,
                                   segment: 1, isPartial: false,
                                   anchor: head, latestTimestamp: head.timestamp)
    #expect(resumed.measuredDistance == 68)

    // A fix older than the restored head is still refused.
    #expect(resumed.ingest(LocationFix(latitude: 48.85, longitude: 2.352, horizontalAccuracy: 5,
                                       timestamp: Date(timeIntervalSince1970: 1_005)))
            == .ignoredDuplicateOrOld)
    // A new far-away point continues the numbering instead of restarting at segment 1.
    #expect(resumed.ingest(LocationFix(latitude: 48.85, longitude: 2.40, horizontalAccuracy: 5,
                                       timestamp: Date(timeIntervalSince1970: 1_600)))
            == .anchor(segment: 2))
    #expect(resumed.measuredEdgeCount == 1)
}