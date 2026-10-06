import Foundation
import SwiftData

@Model
final class DogRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var breedKind: String
    var breedLabel: String
    // Property defaults double as CoreData migration defaults: without them the
    // lightweight V2->V3 stage refuses to fill existing rows
    // ("missing attribute values on mandatory destination attribute").
    var ageDescription: String = ""
    var gender: String = "unspecified"
    var preferencesNote: String = ""
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        breedKind: String,
        breedLabel: String = "",
        ageDescription: String = "",
        gender: String = "unspecified",
        preferencesNote: String = "",
        photoData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.breedKind = breedKind
        self.breedLabel = breedLabel
        self.ageDescription = ageDescription
        self.gender = gender
        self.preferencesNote = preferencesNote
        self.photoData = photoData
        self.createdAt = .now
    }

    /// Human label for the picker's raw kind. Kept next to the stored column so
    /// every screen describes a breed the same way.
    var breedDescription: String {
        switch breedKind {
        case "known": breedLabel
        case "mixed": "Croisé"
        default: "Race inconnue"
        }
    }

    var genderDescription: String {
        switch gender {
        case "male": "Mâle"
        case "female": "Femelle"
        default: "Non renseigné"
        }
    }
}

/// The single walk entity: a manual entry is a session with no points, not a second
/// kind of walk. Never multiplied by the number of dogs present.
///
/// Phase, source and quality are three independent axes and are stored as raw strings
/// so the schema never depends on a Swift enum's shape.
@Model
final class WalkRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    /// Nil until the walk is finished, so a live session needs no second schema change.
    var endedAt: Date?
    var confirmedSeconds: Double
    var phaseRaw: String
    var sourceRaw: String
    var qualityRaw: String
    /// Nil means "not measured", which is different from a measured zero.
    var recordedPathMeters: Double?
    var measuredEdgeCount: Int
    var trackSegmentCount: Int
    var revision: Int
    var lastCheckpointAt: Date
    var note: String
    /// Set when the person corrects a finished walk (PRD F05: corrections stay
    /// identified). Nil for a walk as recorded or entered. Optional with a nil
    /// default, so the V3 to V4 lightweight stage fills existing rows.
    var correctedAt: Date? = nil

    init(id: UUID = UUID(),
         startedAt: Date,
         endedAt: Date? = nil,
         confirmedSeconds: TimeInterval = 0,
         phase: WalkPhase = .recording,
         source: WalkSource = .manual,
         quality: WalkQuality = .unavailable,
         note: String = "") {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.confirmedSeconds = confirmedSeconds
        self.phaseRaw = phase.rawValue
        self.sourceRaw = source.rawValue
        self.qualityRaw = quality.rawValue
        self.recordedPathMeters = nil
        self.measuredEdgeCount = 0
        self.trackSegmentCount = 0
        self.revision = 0
        self.lastCheckpointAt = startedAt
        self.note = note
    }

    var phase: WalkPhase {
        get { WalkPhase(rawValue: phaseRaw) ?? .interrupted }
        set { phaseRaw = newValue.rawValue }
    }

    var source: WalkSource {
        get { WalkSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var quality: WalkQuality {
        get { WalkQuality(rawValue: qualityRaw) ?? .unavailable }
        set { qualityRaw = newValue.rawValue }
    }

    /// A finished, declaratively entered walk. No points, no distance, no invention.
    static func manual(endedAt: Date, durationSeconds: TimeInterval, note: String = "") -> WalkRecord {
        WalkRecord(startedAt: endedAt.addingTimeInterval(-durationSeconds),
                   endedAt: endedAt,
                   confirmedSeconds: durationSeconds,
                   phase: .completed,
                   source: .manual,
                   quality: .manual,
                   note: note)
    }

    /// A live GPS session. Duration accrues from monotonic deltas supplied by the
    /// coordinator, never from a wall-clock difference after a cold launch.
    static func gpsSession(startedAt: Date) -> WalkRecord {
        WalkRecord(startedAt: startedAt,
                   endedAt: nil,
                   confirmedSeconds: 0,
                   phase: .recording,
                   source: .gps,
                   quality: .unavailable)
    }
}

// Explicit links: the repository, not SwiftData, must maintain referential integrity.
// The first starter supports global erasure; individual deletion is a later tested command.
@Model
final class WalkDogRecord {
    @Attribute(.unique) var id: UUID
    var walkID: UUID
    var dogID: UUID
    var dogNameSnapshot: String

    init(walkID: UUID, dogID: UUID, dogNameSnapshot: String) {
        self.id = UUID()
        self.walkID = walkID
        self.dogID = dogID
        self.dogNameSnapshot = dogNameSnapshot
    }
}

/// A private, local coordinate. Never part of a public DTO and never sent by default.
@Model
final class TrackPointRecord {
    @Attribute(.unique) var id: UUID
    var walkID: UUID
    /// Contiguous per walk, assigned by the single writer.
    var sequence: Int
    var segment: Int
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var timestamp: Date

    init(id: UUID = UUID(),
         walkID: UUID,
         sequence: Int,
         segment: Int,
         latitude: Double,
         longitude: Double,
         horizontalAccuracy: Double,
         timestamp: Date) {
        self.id = id
        self.walkID = walkID
        self.sequence = sequence
        self.segment = segment
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}
