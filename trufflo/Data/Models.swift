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
    // V7 (2026-10-07 mock-up): declared by the person, never inferred.
    /// "small", "medium", "large", or empty when not given.
    var sizeRaw: String = ""
    var weightKg: Double? = nil
    /// Comma-separated trait keys from `DogTrait`, in the order chosen.
    var traitsRaw: String = ""

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

    var size: DogSize? { DogSize(rawValue: sizeRaw) }
    var traits: [DogTrait] { DogTrait.list(from: traitsRaw) }

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
    // V7 (2026-10-07 mock-up).
    /// A title the person gives; empty means the screens fall back to the dogs.
    var title: String = ""
    /// A `WalkMood` key, or empty.
    var moodRaw: String = ""
    /// Where a balade suivie took place, from its tracé; empty when unknown.
    var placeName: String = ""
    /// A `WalkWeather` condition key and the temperature at the end, when known.
    var weatherRaw: String = ""
    var temperatureC: Double? = nil

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

    var mood: WalkMood? { WalkMood(rawValue: moodRaw) }
    var weather: WalkWeather? { WalkWeather(rawValue: weatherRaw) }

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

/// The routine a person chose for one dog (PRD F04). At most one per dog.
/// Stored apart from the dog so pausing or deleting it never touches the
/// profile or the history. Optional numbers are stored as 0 for "not chosen"
/// to keep the columns simple; the domain type is the reading of record.
@Model
final class RoutineRecord {
    @Attribute(.unique) var dogID: UUID
    // Stored column names, kept as written on every device: the glossary says
    // "balade" (walk), and `DogRoutine` does, but renaming these needs a migration.
    var outingsPerDay: Int
    var minutesPerOuting: Int
    /// Comma-separated `DogRoutine.Slot` raw values, empty for none.
    var slotsRaw: String
    var isPaused: Bool
    var updatedAt: Date

    init(dogID: UUID, routine: DogRoutine, isPaused: Bool = false, at date: Date = .now) {
        self.dogID = dogID
        self.outingsPerDay = routine.walksPerDay ?? 0
        self.minutesPerOuting = routine.minutesPerWalk ?? 0
        self.slotsRaw = routine.slots.sorted().map(\.rawValue).joined(separator: ",")
        self.isPaused = isPaused
        self.updatedAt = date
    }

    func apply(_ routine: DogRoutine, at date: Date = .now) {
        outingsPerDay = routine.walksPerDay ?? 0
        minutesPerOuting = routine.minutesPerWalk ?? 0
        slotsRaw = routine.slots.sorted().map(\.rawValue).joined(separator: ",")
        updatedAt = date
    }

    var routine: DogRoutine? {
        let slots = Set(slotsRaw.split(separator: ",").compactMap { DogRoutine.Slot(rawValue: String($0)) })
        return try? DogRoutine(walksPerDay: outingsPerDay > 0 ? outingsPerDay : nil,
                               minutesPerWalk: minutesPerOuting > 0 ? minutesPerOuting : nil,
                               slots: slots)
    }
}

/// A photo the person attached to a balade. Stays on this iPhone: never part of
/// what the household receives. Resized and stripped of its location on import.
@Model
final class WalkPhotoRecord {
    @Attribute(.unique) var id: UUID
    var walkID: UUID
    @Attribute(.externalStorage) var data: Data
    var createdAt: Date

    init(id: UUID = UUID(), walkID: UUID, data: Data, createdAt: Date = .now) {
        self.id = id
        self.walkID = walkID
        self.data = data
        self.createdAt = createdAt
    }
}

/// A balade the person plans: when, and where if they say so (2026-10-07 board,
/// "Prochaine balade"). One upcoming plan at a time; it goes when walked or past.
@Model
final class PlannedWalkRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var placeName: String
    var latitude: Double?
    var longitude: Double?
    var remind: Bool

    init(id: UUID = UUID(), date: Date, placeName: String = "", latitude: Double? = nil,
         longitude: Double? = nil, remind: Bool = true) {
        self.id = id
        self.date = date
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.remind = remind
    }
}
