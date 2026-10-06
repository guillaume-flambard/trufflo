import Foundation
import SwiftData

/// What one synchronisation did, for the screen and for the tests.
struct SyncReport: Equatable {
    var dogsSent = 0
    var walksSent = 0
    var tombstonesSent = 0
    var walksReceived = 0
    var walksRemoved = 0
    var failures = 0
    var revoked = false
    var skippedNoHousehold = false
}

/// The household synchronisation (PRD F08, chantier 3 spec S1 to S16).
///
/// Push: every finished local walk and every own dog goes up as a summary,
/// once per change, judged by a fingerprint of exactly what is sent. A local
/// item that disappeared goes up as a tombstone, once. Pull: walks of the
/// other members come down into `SharedWalkRecord`, read-only.
///
/// The journal tables are only read here, never written: sharing never
/// changes a person's own walks.
@MainActor
struct HouseholdSync {
    private let context: ModelContext
    private let remote: any HouseholdRemote
    private let now: () -> Date

    /// Pull window overlap, against clocks that disagree (spec S9, R-37).
    static let pullOverlap: TimeInterval = 60

    init(context: ModelContext, remote: any HouseholdRemote, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.remote = remote
        self.now = now
    }

    // MARK: - Reading

    func household() -> HouseholdRecord? {
        try? context.fetch(FetchDescriptor<HouseholdRecord>()).first
    }

    func state(ofWalk id: UUID) -> SyncState {
        guard household() != nil else { return .localOnly }
        let key = SyncLedgerRecord.key(.walk, id)
        let entry = try? context.fetch(FetchDescriptor<SyncLedgerRecord>(predicate: #Predicate { $0.key == key })).first
        return entry?.state ?? .pending
    }

    // MARK: - Joining and leaving

    /// Creates a household with this person as its owner, then shares the journal.
    @discardableResult
    func createHousehold(name: String, displayName: String) async throws -> SyncReport {
        guard household() == nil else { throw RemoteError.rejected("one household at a time") }
        let id = UUID()
        let me = try await remote.currentUserID()
        try await remote.createHousehold(id: id, name: name)
        try await remote.setDisplayName(displayName, householdID: id, userID: me)
        context.insert(HouseholdRecord(id: id, name: name, myUserID: me, myRole: .owner,
                                       myDisplayName: displayName, joinedAt: now()))
        try context.save()
        return try await sync()
    }

    /// First half of joining: accept the invite and return what the
    /// household already has, so the person can say which dog is which.
    func acceptInvite(token: String) async throws -> (household: HouseholdDTO, dogs: [RemoteDogDTO]) {
        guard household() == nil else { throw RemoteError.rejected("one household at a time") }
        let id = try await remote.acceptInvite(token: token)
        return try await prepareJoin(id)
    }

    /// The household this person already belongs to on the server, if this
    /// iPhone has forgotten it (reinstall, sign-out). The first one: the app
    /// handles one household at a time.
    func householdToResume() async throws -> HouseholdDTO? {
        guard household() == nil else { return nil }
        return try await remote.myHouseholds().first
    }

    /// Resuming goes through the same dog step as joining: the local dogs of
    /// this iPhone may not be the ones it had before.
    func resume(_ household: HouseholdDTO) async throws -> (household: HouseholdDTO, dogs: [RemoteDogDTO]) {
        try await prepareJoin(household.id)
    }

    private func prepareJoin(_ id: UUID) async throws -> (household: HouseholdDTO, dogs: [RemoteDogDTO]) {
        guard let household = try await remote.household(id: id) else { throw RemoteError.forbidden("household") }
        let dogs = try await remote.dogs(householdID: id).filter { $0.deletedAt == nil }
        return (household, dogs)
    }

    /// Second half of joining: record which local dog is which household dog
    /// (nil: bring it into the household as a new dog), then synchronise.
    @discardableResult
    func completeJoin(_ joined: HouseholdDTO, displayName: String,
                      links: [UUID: UUID?]) async throws -> SyncReport {
        guard household() == nil else { throw RemoteError.rejected("one household at a time") }
        let me = try await remote.currentUserID()
        let role = try await remote.members(householdID: joined.id).first { $0.userID == me }?.role ?? .reader
        try await remote.setDisplayName(displayName, householdID: joined.id, userID: me)
        context.insert(HouseholdRecord(id: joined.id, name: joined.name, myUserID: me, myRole: role,
                                       myDisplayName: displayName, joinedAt: now()))
        for (local, remoteID) in links {
            context.insert(DogLinkRecord(localDogID: local, remoteDogID: remoteID ?? local))
        }
        try context.save()
        return try await sync()
    }

    func createInvite(role: HouseholdRole) async throws -> String {
        guard let household = household() else { throw RemoteError.forbidden("no household") }
        return try await remote.createInvite(householdID: household.id, role: role)
    }

    /// Leaves on the server, then forgets everything received (spec S11).
    func leave() async throws {
        guard let household = household() else { return }
        try await remote.leave(householdID: household.id, userID: household.myUserID)
        try purge()
    }

    /// Forgets the household on this iPhone: received walks, members, links,
    /// ledger. The person's own dogs and walks are untouched (spec S10).
    func purge() throws {
        for type in [SharedWalkRecord.self, HouseholdMemberRecord.self, DogLinkRecord.self,
                     SyncLedgerRecord.self, HouseholdRecord.self] as [any PersistentModel.Type] {
            try context.delete(model: type)
        }
        try context.save()
    }

    // MARK: - Synchronising

    @discardableResult
    func sync() async throws -> SyncReport {
        var report = SyncReport()
        guard let household = household() else {
            report.skippedNoHousehold = true
            return report
        }
        do {
            guard try await remote.household(id: household.id) != nil else {
                try purge()
                report.revoked = true
                return report
            }
            try await refreshMembers(household)
            if household.myRole != .reader {
                try await pushDogs(household, into: &report)
                try await pushWalks(household, into: &report)
            }
            try await pullWalks(household, into: &report)
            household.lastSyncAt = now()
            household.lastError = report.failures > 0 ? "Certaines balades n'ont pas été envoyées." : nil
            try context.save()
            return report
        } catch let error as RemoteError {
            household.lastError = error.message
            try? context.save()
            throw error
        }
    }

    private func refreshMembers(_ household: HouseholdRecord) async throws {
        let members = try await remote.members(householdID: household.id)
        try context.delete(model: HouseholdMemberRecord.self)
        for member in members {
            let name = member.displayName ?? "Membre du foyer"
            context.insert(HouseholdMemberRecord(userID: member.userID, displayName: name, role: member.role))
            if member.userID == household.myUserID { household.myRoleRaw = member.role.rawValue }
        }
    }

    // MARK: Push

    private func pushDogs(_ household: HouseholdRecord, into report: inout SyncReport) async throws {
        let dogs = try context.fetch(FetchDescriptor<DogRecord>())
        var links = try linksByLocalID()
        for dog in dogs where links[dog.id] == nil {
            // A dog created after joining enters the household as itself.
            let link = DogLinkRecord(localDogID: dog.id, remoteDogID: dog.id)
            context.insert(link)
            links[dog.id] = link.remoteDogID
        }
        var ledger = try ledgerEntries(.dog)
        for dog in dogs where links[dog.id] == dog.id {
            let dto = DogDTO(id: dog.id, householdID: household.id, name: dog.name,
                             breedKind: dog.breedKind, breedLabel: dog.breedLabel,
                             ageDescription: dog.ageDescription)
            let entry = ledger[dog.id] ?? insertLedger(.dog, dog.id)
            ledger[dog.id] = entry
            let fingerprint = SyncFingerprint.of(dto)
            guard entry.pushedFingerprint != fingerprint else { continue }
            try await send(entry, fingerprint: fingerprint, report: &report) {
                try await remote.upsertDog(dto)
            }
            if entry.state == .synced { report.dogsSent += 1 }
        }
        // Own dogs deleted locally go up as tombstones; a dog that was only a
        // link to someone else's dog is simply forgotten.
        let present = Set(dogs.map(\.id))
        for (localID, entry) in ledger where !present.contains(localID)
            && entry.pushedFingerprint != SyncLedgerRecord.tombstoneFingerprint {
            try await send(entry, fingerprint: SyncLedgerRecord.tombstoneFingerprint, report: &report) {
                try await remote.tombstoneDog(id: localID, at: now())
            }
            if entry.state == .synced { report.tombstonesSent += 1 }
        }
        for (localID, link) in try linkRecords() where !present.contains(localID) && !link.isOwnDog {
            context.delete(link)
        }
        try context.save()
    }

    private func pushWalks(_ household: HouseholdRecord, into report: inout SyncReport) async throws {
        let links = try linksByLocalID()
        let walks = try context.fetch(FetchDescriptor<WalkRecord>())
        var ledger = try ledgerEntries(.walk)
        for walk in walks {
            guard let push = try walkPush(walk, household: household, links: links) else { continue }
            let entry = ledger[walk.id] ?? insertLedger(.walk, walk.id)
            ledger[walk.id] = entry
            let fingerprint = push.fingerprint
            guard entry.pushedFingerprint != fingerprint else { continue }
            try await send(entry, fingerprint: fingerprint, report: &report) {
                try await remote.upsertWalk(push.walk)
                try await remote.replaceParticipants(walkID: walk.id, with: push.dogs)
            }
            if entry.state == .synced { report.walksSent += 1 }
        }
        let present = Set(walks.map(\.id))
        for (localID, entry) in ledger where !present.contains(localID)
            && entry.pushedFingerprint != SyncLedgerRecord.tombstoneFingerprint {
            // Never sent alive: nothing to delete on the server.
            if entry.pushedFingerprint == nil {
                context.delete(entry)
                continue
            }
            try await send(entry, fingerprint: SyncLedgerRecord.tombstoneFingerprint, report: &report) {
                try await remote.tombstoneWalk(id: localID, at: now())
            }
            if entry.state == .synced { report.tombstonesSent += 1 }
        }
        try context.save()
    }

    /// The exact payload for one walk, or nil while it is not finished (S3).
    func walkPush(_ walk: WalkRecord, household: HouseholdRecord,
                  links: [UUID: UUID]) throws -> WalkPush? {
        guard let endedAt = walk.endedAt,
              walk.phase == .completed || walk.phase == .interrupted else { return nil }
        let walkID = walk.id
        let participants = try context.fetch(FetchDescriptor<WalkDogRecord>(
            predicate: #Predicate { $0.walkID == walkID }))
        let dogs = participants.compactMap { participant -> WalkDogDTO? in
            guard let remoteDog = links[participant.dogID] else { return nil }
            return WalkDogDTO(walkID: walkID, dogID: remoteDog, dogNameSnapshot: participant.dogNameSnapshot)
        }.sorted { $0.dogID.uuidString < $1.dogID.uuidString }
        let summary = WalkSummaryDTO(
            id: walkID, householdID: household.id,
            source: walk.source.rawValue, quality: walk.quality.rawValue,
            startedAt: walk.startedAt, endedAt: max(endedAt, walk.startedAt),
            confirmedSeconds: walk.confirmedSeconds,
            recordedPathMeters: walk.source == .gps ? walk.recordedPathMeters : nil,
            correctedAt: walk.correctedAt)
        return WalkPush(walk: summary, dogs: dogs)
    }

    /// Runs one send. Offline and signed-out stop the whole sync and change
    /// nothing; a refusal for this item is kept on the item and the sync goes on.
    private func send(_ entry: SyncLedgerRecord, fingerprint: String, report: inout SyncReport,
                      _ work: () async throws -> Void) async throws {
        do {
            try await work()
            entry.pushedFingerprint = fingerprint
            entry.state = .synced
            entry.lastError = nil
        } catch let error as RemoteError {
            switch error {
            case .offline, .signedOut, .server:
                entry.state = .pending
                throw error
            case .forbidden, .rejected:
                entry.state = .failed
                entry.lastError = error.message
                report.failures += 1
            }
        }
        entry.updatedAt = now()
    }

    // MARK: Pull

    private func pullWalks(_ household: HouseholdRecord, into report: inout SyncReport) async throws {
        let since = household.lastPulledAt.map { $0.addingTimeInterval(-Self.pullOverlap) }
        let walks = try await remote.walks(householdID: household.id, changedSince: since)
        var newest = household.lastPulledAt
        let existing = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<SharedWalkRecord>()).map { ($0.id, $0) })
        // My own walks stay in my journal and never come back as copies. One
        // exception: a walk of mine this iPhone no longer has (reinstall,
        // another iPhone) comes back read-only, like anyone else's summary.
        // The ledger counts too: a walk deleted here whose tombstone has not
        // gone up yet must not come back as a copy.
        let localWalkIDs = Set(try context.fetch(FetchDescriptor<WalkRecord>()).map(\.id))
            .union(try ledgerEntries(.walk).keys)
        for walk in walks {
            if newest.map({ walk.updatedAt > $0 }) ?? true { newest = walk.updatedAt }
            guard !localWalkIDs.contains(walk.id) else { continue }
            if walk.deletedAt != nil {
                if let copy = existing[walk.id] {
                    context.delete(copy)
                    report.walksRemoved += 1
                }
            } else if let copy = existing[walk.id] {
                if copy.revision != walk.revision || copy.updatedAt != walk.updatedAt {
                    copy.apply(walk)
                    report.walksReceived += 1
                }
            } else {
                context.insert(SharedWalkRecord(walk))
                report.walksReceived += 1
            }
        }
        household.lastPulledAt = newest
        try context.save()
    }

    // MARK: Plumbing

    private func linkRecords() throws -> [UUID: DogLinkRecord] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<DogLinkRecord>()).map { ($0.localDogID, $0) })
    }

    private func linksByLocalID() throws -> [UUID: UUID] {
        try linkRecords().mapValues(\.remoteDogID)
    }

    private func ledgerEntries(_ kind: SyncItemKind) throws -> [UUID: SyncLedgerRecord] {
        let raw = kind.rawValue
        let entries = try context.fetch(FetchDescriptor<SyncLedgerRecord>(predicate: #Predicate { $0.kindRaw == raw }))
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.localID, $0) })
    }

    private func insertLedger(_ kind: SyncItemKind, _ id: UUID) -> SyncLedgerRecord {
        let entry = SyncLedgerRecord(kind: kind, localID: id, at: now())
        context.insert(entry)
        return entry
    }
}
