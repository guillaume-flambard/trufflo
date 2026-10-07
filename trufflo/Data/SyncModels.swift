import Foundation
import SwiftData

// The shared household (PRD F08), schema V6. These tables sit beside the
// journal and never change a journal row: a walk stays a walk whether or not
// it was shared. Erasing them leaves the person's own journal intact.

/// The household this iPhone has joined. At most one row (spec: one household
/// at a time).
@Model
final class HouseholdRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var myUserID: UUID
    var myRoleRaw: String
    var myDisplayName: String
    var joinedAt: Date
    /// Newest `updated_at` received from the server; nil before the first pull.
    var lastPulledAt: Date?
    var lastSyncAt: Date?
    /// The last failure, kept until a sync succeeds. Nil when all is well.
    var lastError: String?

    init(id: UUID, name: String, myUserID: UUID, myRole: HouseholdRole,
         myDisplayName: String, joinedAt: Date = .now) {
        self.id = id
        self.name = name
        self.myUserID = myUserID
        self.myRoleRaw = myRole.rawValue
        self.myDisplayName = myDisplayName
        self.joinedAt = joinedAt
    }

    var myRole: HouseholdRole { HouseholdRole(rawValue: myRoleRaw) ?? .reader }
}

/// Which household dog a local dog is. A dog the person brought into the
/// household links to itself.
@Model
final class DogLinkRecord {
    @Attribute(.unique) var localDogID: UUID
    var remoteDogID: UUID

    init(localDogID: UUID, remoteDogID: UUID) {
        self.localDogID = localDogID
        self.remoteDogID = remoteDogID
    }

    var isOwnDog: Bool { localDogID == remoteDogID }
}

/// What was last sent for one local item, so an unchanged item is never sent
/// twice and a deleted one is sent as a tombstone, once.
@Model
final class SyncLedgerRecord {
    /// `walk:<uuid>` or `dog:<uuid>`.
    @Attribute(.unique) var key: String
    var kindRaw: String
    var localID: UUID
    var pushedFingerprint: String?
    var stateRaw: String
    var lastError: String?
    var updatedAt: Date

    init(kind: SyncItemKind, localID: UUID, at date: Date = .now) {
        self.key = SyncLedgerRecord.key(kind, localID)
        self.kindRaw = kind.rawValue
        self.localID = localID
        self.stateRaw = SyncState.pending.rawValue
        self.updatedAt = date
    }

    static func key(_ kind: SyncItemKind, _ id: UUID) -> String { "\(kind.rawValue):\(id.uuidString)" }

    var state: SyncState {
        get { SyncState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    var kind: SyncItemKind { SyncItemKind(rawValue: kindRaw) ?? .walk }

    static let tombstoneFingerprint = "deleted"
}

enum SyncItemKind: String, Sendable { case walk, dog, plan }

/// DATA-CONTRACTS §3. `conflict` is never produced in this version: the
/// server is the authority and an author's last write wins (ADR 0008).
enum SyncState: String, Sendable { case localOnly, pending, synced, conflict, failed }

/// A walk recorded by another member, read-only on this iPhone. It carries
/// what the server shares and nothing more: no track, no note.
@Model
final class SharedWalkRecord {
    @Attribute(.unique) var id: UUID
    var authorID: UUID
    var startedAt: Date
    var endedAt: Date
    var confirmedSeconds: Double
    var recordedPathMeters: Double?
    var qualityRaw: String
    var sourceRaw: String
    var revision: Int
    var correctedAt: Date?
    /// Household dog ids, joined by `separator`, sorted by name.
    var dogIDsRaw: String
    /// Dog names at the time of the walk, joined by `separator`: a name may
    /// contain a comma, it cannot contain a control character.
    var dogNamesRaw: String
    var updatedAt: Date
    // What the author wrote and the phone measured (V7). Empty or nil on a walk shared by
    // an older version of the app.
    var title: String = ""
    var moodRaw: String = ""
    var weatherRaw: String = ""
    var temperatureC: Double? = nil

    init(_ walk: RemoteWalkDTO) {
        id = walk.id
        authorID = walk.authorID
        startedAt = walk.startedAt
        endedAt = walk.endedAt
        confirmedSeconds = walk.confirmedSeconds
        recordedPathMeters = walk.recordedPathMeters
        qualityRaw = walk.quality
        sourceRaw = walk.source
        revision = walk.revision
        correctedAt = walk.correctedAt
        dogIDsRaw = ""
        dogNamesRaw = ""
        updatedAt = walk.updatedAt
        apply(walk)
    }

    func apply(_ walk: RemoteWalkDTO) {
        startedAt = walk.startedAt
        endedAt = walk.endedAt
        confirmedSeconds = walk.confirmedSeconds
        recordedPathMeters = walk.recordedPathMeters
        qualityRaw = walk.quality
        sourceRaw = walk.source
        revision = walk.revision
        correctedAt = walk.correctedAt
        let dogs = walk.dogs.sorted { $0.dogNameSnapshot < $1.dogNameSnapshot }
        dogIDsRaw = dogs.map(\.dogID.uuidString).joined(separator: Self.separator)
        dogNamesRaw = dogs.map(\.dogNameSnapshot).joined(separator: Self.separator)
        updatedAt = walk.updatedAt
        title = walk.title
        moodRaw = walk.mood ?? ""
        weatherRaw = walk.weather ?? ""
        temperatureC = walk.temperatureC
    }

    static let separator = "\u{1F}"

    var dogIDs: [UUID] { dogIDsRaw.split(separator: Self.separator).compactMap { UUID(uuidString: String($0)) } }
    var dogNames: [String] { dogNamesRaw.split(separator: Self.separator).map(String.init) }
    var quality: WalkQuality { WalkQuality(rawValue: qualityRaw) ?? .unavailable }
    var source: WalkSource { WalkSource(rawValue: sourceRaw) ?? .manual }
    var mood: WalkMood? { WalkMood(rawValue: moodRaw) }
    var weather: WalkWeather? { WalkWeather(rawValue: weatherRaw) }
}

/// A balade another member plans (V7), read-only here: who, when, and the
/// name of the place. Replaced at every sync by what the server lists.
@Model
final class SharedPlannedWalkRecord {
    @Attribute(.unique) var id: UUID
    var authorID: UUID
    var plannedAt: Date
    var placeName: String

    init(_ plan: RemotePlannedWalkDTO) {
        id = plan.id
        authorID = plan.authorID
        plannedAt = plan.plannedAt
        placeName = plan.placeName
    }
}

/// A member of the household as the others see them.
@Model
final class HouseholdMemberRecord {
    @Attribute(.unique) var userID: UUID
    var displayName: String
    var roleRaw: String

    init(userID: UUID, displayName: String, role: HouseholdRole) {
        self.userID = userID
        self.displayName = displayName
        self.roleRaw = role.rawValue
    }

    var role: HouseholdRole { HouseholdRole(rawValue: roleRaw) ?? .reader }
}
