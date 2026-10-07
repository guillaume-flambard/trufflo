import Foundation

// The community walk outings, as the app asks for them (ADR 0010, lot C).
// The server is written separately against the same contract; the names in
// CodingKeys and the function names in ADR 0010 « Contrat client » are that
// contract. Nothing here carries a coordinate, a track or a private note.

public struct CommunityZone: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct CommunityProfileDTO: Codable, Equatable, Sendable {
    public var userID: UUID
    public var displayName: String
    public var zoneID: String
    public var adultDeclaredAt: Date
    /// Set by a moderator: the profile sees nothing and can do nothing.
    public var suspended = false

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", displayName = "display_name", zoneID = "zone_id"
        case adultDeclaredAt = "adult_declared_at", suspended
    }

    public init(userID: UUID, displayName: String, zoneID: String, adultDeclaredAt: Date) {
        self.userID = userID
        self.displayName = displayName
        self.zoneID = zoneID
        self.adultDeclaredAt = adultDeclaredAt
    }
}

/// A dog the person chose to show. Never derived from a household dog.
public struct CommunityDogDTO: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var ownerID: UUID
    public var name: String
    public var breedLabel: String
    public var publicNote: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerID = "owner_id", breedLabel = "breed_label", publicNote = "public_note"
    }

    public init(id: UUID, ownerID: UUID, name: String, breedLabel: String = "", publicNote: String = "") {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.breedLabel = breedLabel
        self.publicNote = publicNote
    }
}

public enum OutingStatus: String, Codable, Sendable { case published, cancelled, removed }

public enum ParticipationStatus: String, Codable, Sendable { case requested, accepted, declined, withdrawn }

/// One walk outing as a member of the zone sees it. Places are counted by the
/// server; the list of participants is not part of this row.
public struct OutingDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var organizerID: UUID
    public var organizerName: String
    public var zoneID: String
    public var startsAt: Date
    public var durationMinutes: Int
    public var meetingPoint: String
    public var rules: String
    public var humanCapacity: Int
    public var dogCapacity: Int
    public var humansAccepted: Int
    public var dogsAccepted: Int
    public var status: OutingStatus
    /// This person's own request, if any.
    public var myStatus: ParticipationStatus?
    /// What this person declared about having been there, once it is over.
    public var myAttended: Bool?

    enum CodingKeys: String, CodingKey {
        case id, rules, status
        case organizerID = "organizer_id", organizerName = "organizer_name", zoneID = "zone_id"
        case startsAt = "starts_at", durationMinutes = "duration_minutes", meetingPoint = "meeting_point"
        case humanCapacity = "human_capacity", dogCapacity = "dog_capacity"
        case humansAccepted = "humans_accepted", dogsAccepted = "dogs_accepted", myStatus = "my_status"
        case myAttended = "my_attended"
    }

    public var humanPlacesLeft: Int { max(humanCapacity - humansAccepted, 0) }
    public var dogPlacesLeft: Int { max(dogCapacity - dogsAccepted, 0) }
    public var endsAt: Date { startsAt.addingTimeInterval(Double(durationMinutes) * 60) }
}

/// What an organizer writes. Validated here and again by the server.
public struct OutingDraft: Codable, Equatable, Sendable {
    public var startsAt: Date
    public var durationMinutes: Int
    public var meetingPoint: String
    public var rules: String
    public var humanCapacity: Int
    public var dogCapacity: Int

    enum CodingKeys: String, CodingKey {
        case rules
        case startsAt = "starts_at", durationMinutes = "duration_minutes", meetingPoint = "meeting_point"
        case humanCapacity = "human_capacity", dogCapacity = "dog_capacity"
    }

    public init(startsAt: Date, durationMinutes: Int, meetingPoint: String, rules: String,
                humanCapacity: Int, dogCapacity: Int, now: Date = .now) throws {
        let point = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRules = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard startsAt > now else { throw CommunityError.invalid("La sortie doit être à venir.") }
        guard (15...240).contains(durationMinutes) else { throw CommunityError.invalid("Une durée entre 15 minutes et 4 heures.") }
        guard (1...120).contains(point.count) else { throw CommunityError.invalid("Indiquez un point de rendez-vous public.") }
        guard cleanRules.count <= 500 else { throw CommunityError.invalid("Les règles tiennent en 500 caractères.") }
        guard (1...30).contains(humanCapacity), (1...30).contains(dogCapacity) else {
            throw CommunityError.invalid("Entre 1 et 30 places.")
        }
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.meetingPoint = point
        self.rules = cleanRules
        self.humanCapacity = humanCapacity
        self.dogCapacity = dogCapacity
    }
}

/// A participant as the organizer, or another accepted participant, sees them.
public struct OutingParticipantDTO: Codable, Equatable, Sendable, Identifiable {
    public var userID: UUID
    public var displayName: String
    public var status: ParticipationStatus
    public var dogNames: [String]
    public var attended: Bool?

    public var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case status, attended
        case userID = "user_id", displayName = "display_name", dogNames = "dog_names"
    }
}

public enum OutingUpdateKind: String, Codable, Sendable { case time, place, cancelled }

public struct OutingUpdateDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var outingID: UUID
    public var kind: OutingUpdateKind
    public var previous: String
    public var current: String
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, previous, current
        case outingID = "outing_id", createdAt = "created_at"
    }
}

/// Someone this person blocked, by the name they chose, so it can be undone.
public struct BlockedPersonDTO: Codable, Equatable, Sendable, Identifiable {
    public var userID: UUID
    public var displayName: String
    public var id: UUID { userID }

    enum CodingKeys: String, CodingKey { case userID = "user_id", displayName = "display_name" }

    public init(userID: UUID, displayName: String) {
        self.userID = userID
        self.displayName = displayName
    }
}

/// Where people reach the team (Apple 1.2: published contact information).
/// Set from decision D6, with the responsible person; until it is set the
/// pilot is not opened to the public (docs/specs/C-premiere-sortie.md C-REQ-09).
public enum CommunityContact {
    public static let url: URL? = nil
    public static var isConfigured: Bool { url != nil }
}

public enum ReportTarget: String, Codable, Sendable { case outing, profile, dog }
public enum ReportReason: String, Codable, Sendable, CaseIterable { case danger, harassment, inappropriate, spam, other }

/// Failures the person can act on. The server's refusals are mapped from the
/// message it raises (ADR 0010 « Contrat client »).
public enum CommunityError: Error, Equatable, Sendable {
    case invalid(String)
    case noProfile
    case notAllowed
    case outingFull
    case outingGone
    case blocked
    /// No session, or one the server refused: the person must sign in again.
    case signedOut
    /// No network, or the server did not answer.
    case offline
    case network(String)

    public init(serverMessage message: String) {
        if message.contains("outing full") { self = .outingFull }
        else if message.contains("outing gone") { self = .outingGone }
        else if message.contains("blocked") { self = .blocked }
        else if message.contains("no profile") { self = .noProfile }
        else if message.contains("not allowed") { self = .notAllowed }
        else { self = .network(message) }
    }
}

/// Everything the app asks of the community server.
public protocol CommunityRemote: Sendable {
    func currentUserID() async throws -> UUID
    /// Open zones only.
    func zones() async throws -> [CommunityZone]

    func myProfile() async throws -> CommunityProfileDTO?
    /// Creates or updates the profile. `adultDeclared` must be true.
    func saveProfile(displayName: String, zoneID: String, adultDeclared: Bool) async throws
    func myDogs() async throws -> [CommunityDogDTO]
    func saveDog(_ dog: CommunityDogDTO) async throws
    func deleteDog(id: UUID) async throws

    /// Published outings of the zone from yesterday on, blocks applied.
    func outings(zoneID: String) async throws -> [OutingDTO]
    /// Outings this person organizes or has a request in, whatever their date.
    func myOutings() async throws -> [OutingDTO]
    func participants(outingID: UUID) async throws -> [OutingParticipantDTO]
    func updates(outingID: UUID) async throws -> [OutingUpdateDTO]

    func requestToJoin(outingID: UUID, dogIDs: [UUID]) async throws
    func withdraw(outingID: UUID) async throws
    func declareAttendance(outingID: UUID, attended: Bool) async throws

    /// True when this person was registered as an organizer of the zone, by hand.
    func isOrganizer(zoneID: String) async throws -> Bool
    /// Organizers of the zone only. Returns the new outing's identifier.
    func createOuting(_ draft: OutingDraft, zoneID: String) async throws -> UUID
    func decide(outingID: UUID, userID: UUID, accept: Bool) async throws
    func updateOuting(outingID: UUID, startsAt: Date, meetingPoint: String) async throws
    func cancelOuting(outingID: UUID) async throws

    func report(_ target: ReportTarget, id: UUID, reason: ReportReason, detail: String) async throws
    func block(userID: UUID) async throws
    func unblock(userID: UUID) async throws
    func blockedPeople() async throws -> [BlockedPersonDTO]
}
