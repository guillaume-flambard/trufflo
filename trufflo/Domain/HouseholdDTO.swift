import CryptoKit
import Foundation

// What leaves the iPhone for a shared household, and what comes back (PRD F08,
// DATA-CONTRACTS §5). Each type lists its fields explicitly: a note, a
// coordinate or a photo cannot leak through a forgotten property, because
// there is no property to forget. Never import SwiftData or SwiftUI here.

public enum HouseholdRole: String, Codable, Sendable, CaseIterable {
    case owner, contributor, reader

    public var label: String {
        switch self {
        case .owner: "Responsable"
        case .contributor: "Contributeur"
        case .reader: "Lecteur"
        }
    }
}

/// A walk summary as the server stores it. No note, no track, no place.
public struct WalkSummaryDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var source: String
    public var quality: String
    public var startedAt: Date
    public var endedAt: Date
    public var confirmedSeconds: Double
    /// Nil means "not measured", never zero. Always nil for a declared walk.
    public var recordedPathMeters: Double?
    public var correctedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case source, quality
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case confirmedSeconds = "confirmed_seconds"
        case recordedPathMeters = "recorded_path_meters"
        case correctedAt = "corrected_at"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(householdID, forKey: .householdID)
        try c.encode(source, forKey: .source)
        try c.encode(quality, forKey: .quality)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(confirmedSeconds, forKey: .confirmedSeconds)
        // Explicit nulls: an upsert must clear a distance or a correction mark
        // the server still holds, not leave it in place.
        try c.encode(recordedPathMeters, forKey: .recordedPathMeters)
        try c.encode(correctedAt, forKey: .correctedAt)
    }
}

/// One dog taking part in a walk, under the household's dog id.
public struct WalkDogDTO: Codable, Equatable, Sendable {
    public var walkID: UUID
    public var dogID: UUID
    public var dogNameSnapshot: String

    enum CodingKeys: String, CodingKey {
        case walkID = "walk_id"
        case dogID = "dog_id"
        case dogNameSnapshot = "dog_name_snapshot"
    }
}

/// A dog profile as shared. No photo, no gender, no preferences note.
public struct DogDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var name: String
    public var breedKind: String
    public var breedLabel: String
    public var ageDescription: String

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case name
        case breedKind = "breed_kind"
        case breedLabel = "breed_label"
        case ageDescription = "age_description"
    }
}

/// A dog of the household as read back, tombstone included.
public struct RemoteDogDTO: Decodable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var breedKind: String
    public var breedLabel: String
    public var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case breedKind = "breed_kind"
        case breedLabel = "breed_label"
        case deletedAt = "deleted_at"
    }
}

/// A walk of the household as read back, with its participants.
public struct RemoteWalkDTO: Decodable, Equatable, Sendable {
    public var id: UUID
    public var authorID: UUID
    public var revision: Int
    public var source: String
    public var quality: String
    public var startedAt: Date
    public var endedAt: Date
    public var confirmedSeconds: Double
    public var recordedPathMeters: Double?
    public var correctedAt: Date?
    public var updatedAt: Date
    public var deletedAt: Date?
    public var dogs: [Participant]

    public struct Participant: Decodable, Equatable, Sendable {
        public var dogID: UUID
        public var dogNameSnapshot: String

        enum CodingKeys: String, CodingKey {
            case dogID = "dog_id"
            case dogNameSnapshot = "dog_name_snapshot"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case revision, source, quality
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case confirmedSeconds = "confirmed_seconds"
        case recordedPathMeters = "recorded_path_meters"
        case correctedAt = "corrected_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case dogs = "walk_dogs"
    }
}

public struct HouseholdDTO: Decodable, Equatable, Sendable {
    public var id: UUID
    public var name: String
}

public struct MemberDTO: Decodable, Equatable, Sendable {
    public var userID: UUID
    public var role: HouseholdRole
    public var displayName: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case role
        case displayName = "display_name"
    }
}

/// The exact payload pushed for one walk: the summary plus its participants.
/// Its fingerprint decides whether anything changed since the last push.
public struct WalkPush: Codable, Equatable, Sendable {
    public var walk: WalkSummaryDTO
    public var dogs: [WalkDogDTO]

    public var fingerprint: String { SyncFingerprint.of(self) }
}

public enum SyncFingerprint {
    /// SHA-256 of a stable encoding: sorted keys, fixed date format. Equal
    /// content gives an equal fingerprint on every run and every device.
    public static func of<T: Encodable>(_ value: T) -> String {
        let encoder = HouseholdCoding.encoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// JSON as PostgREST speaks it: ISO 8601 in UTC. Postgres returns six
/// fractional digits, which Foundation's ISO 8601 parsers do not all accept,
/// so the decoder trims to milliseconds before parsing.
public enum HouseholdCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(format(date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            guard let date = parse(raw) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "date \(raw)")
            }
            return date
        }
        return decoder
    }

    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func parse(_ raw: String) -> Date? {
        var text = raw
        // "2026-10-06 17:22:18.705123+00" and "...T...Z" both occur.
        if let space = text.firstIndex(of: " ") { text.replaceSubrange(space...space, with: "T") }
        if let dot = text.firstIndex(of: ".") {
            let afterDot = text.index(after: dot)
            let zoneStart = text[afterDot...].firstIndex(where: { !$0.isNumber }) ?? text.endIndex
            var digits = String(text[afterDot..<zoneStart])
            digits = String((digits + "000").prefix(3))
            text = String(text[..<afterDot]) + digits + String(text[zoneStart...])
        }
        if text.hasSuffix("+00") { text += ":00" }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
