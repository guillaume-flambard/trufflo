import Foundation
@testable import trufflo

/// An in-memory household server with the rules the real one enforces in
/// row level security and triggers (backend/supabase): members only, readers
/// write nothing, a walk keeps its author, an update moves the revision, a
/// tombstone stays a tombstone. One instance is the server; `as(user)` gives
/// a client signed in as that person.
final class FakeHouseholdServer: @unchecked Sendable {
    struct Walk {
        var summary: WalkSummaryDTO
        var authorID: UUID
        var revision: Int
        var updatedAt: Date
        var deletedAt: Date?
        var dogs: [WalkDogDTO]
    }

    private let lock = NSLock()
    private(set) var households: [UUID: String] = [:]
    private(set) var members: [UUID: [UUID: HouseholdRole]] = [:]
    private(set) var names: [UUID: [UUID: String]] = [:]
    private(set) var invites: [String: (household: UUID, role: HouseholdRole, used: Bool)] = [:]
    private(set) var dogs: [UUID: (dto: DogDTO, deletedAt: Date?)] = [:]
    private(set) var walks: [UUID: Walk] = [:]
    /// Every call, in order, for assertions such as "nothing was sent".
    private(set) var calls: [String] = []
    var clock = Date(timeIntervalSince1970: 1_000_000)
    /// When set, every call fails with this error.
    var failure: RemoteError?
    /// Calls refused for this person, as row level security would.
    var refuse: Set<String> = []

    func client(_ user: UUID) -> FakeHouseholdRemote { FakeHouseholdRemote(server: self, user: user) }

    func resetCalls() { locked { calls.removeAll() } }

    fileprivate func run<T>(_ name: String, _ body: () throws -> T) throws -> T {
        try locked {
            calls.append(name)
            if let failure { throw failure }
            if refuse.contains(name) { throw RemoteError.forbidden("rls") }
            clock = clock.addingTimeInterval(1)
            return try body()
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    fileprivate func role(_ user: UUID, in household: UUID) -> HouseholdRole? { members[household]?[user] }

    fileprivate func requireWriter(_ user: UUID, _ household: UUID) throws {
        guard let role = role(user, in: household), role != .reader else { throw RemoteError.forbidden("rls") }
    }

    // Mutations, called by the client under `run`.
    fileprivate func insertHousehold(_ id: UUID, _ name: String, by user: UUID) {
        households[id] = name
        members[id, default: [:]][user] = .owner
    }
    fileprivate func setName(_ name: String, _ household: UUID, _ user: UUID) { names[household, default: [:]][user] = name }
    fileprivate func addInvite(_ token: String, _ household: UUID, _ role: HouseholdRole) { invites[token] = (household, role, false) }
    fileprivate func useInvite(_ token: String, by user: UUID) throws -> UUID {
        guard let invite = invites[token], !invite.used else { throw RemoteError.rejected("invite not valid") }
        invites[token]?.used = true
        members[invite.household, default: [:]][user] = invite.role
        return invite.household
    }
    fileprivate func removeMember(_ user: UUID, _ household: UUID) throws {
        let owners = members[household]?.filter { $0.value == .owner }.map(\.key) ?? []
        if owners == [user] { throw RemoteError.rejected("a household keeps at least one owner") }
        members[household]?[user] = nil
        names[household]?[user] = nil
    }
    fileprivate func putDog(_ dto: DogDTO) { dogs[dto.id] = (dto, dogs[dto.id]?.deletedAt) }
    fileprivate func deleteDog(_ id: UUID, _ date: Date) { dogs[id]?.deletedAt = date }
    fileprivate func putWalk(_ dto: WalkSummaryDTO, by user: UUID) throws {
        if var existing = walks[dto.id] {
            guard existing.authorID == user || role(user, in: dto.householdID) == .owner else {
                throw RemoteError.forbidden("rls")
            }
            existing.summary = dto
            existing.revision += 1
            existing.updatedAt = clock
            walks[dto.id] = existing
        } else {
            walks[dto.id] = Walk(summary: dto, authorID: user, revision: 1, updatedAt: clock, deletedAt: nil, dogs: [])
        }
    }
    fileprivate func setParticipants(_ walkID: UUID, _ dogsIn: [WalkDogDTO]) throws {
        guard let walk = walks[walkID] else { throw RemoteError.rejected("no walk") }
        for dog in dogsIn where dogs[dog.dogID]?.dto.householdID != walk.summary.householdID {
            throw RemoteError.forbidden("dog of another household")
        }
        walks[walkID]?.dogs = dogsIn
    }
    fileprivate func deleteWalk(_ id: UUID, _ date: Date) {
        walks[id]?.deletedAt = date
        walks[id]?.revision += 1
        walks[id]?.updatedAt = clock
    }

    /// The server's own bookkeeping, for a test that edits as the owner.
    func touchWalk(_ id: UUID, confirmedSeconds: Double) {
        locked {
            clock = clock.addingTimeInterval(1)
            walks[id]?.summary.confirmedSeconds = confirmedSeconds
            walks[id]?.revision += 1
            walks[id]?.updatedAt = clock
        }
    }
}

struct FakeHouseholdRemote: HouseholdRemote {
    let server: FakeHouseholdServer
    let user: UUID

    func currentUserID() async throws -> UUID { try server.run("currentUserID") { user } }

    func createHousehold(id: UUID, name: String) async throws {
        try server.run("createHousehold") { server.insertHousehold(id, name, by: user) }
    }

    func household(id: UUID) async throws -> HouseholdDTO? {
        try server.run("household") {
            guard server.role(user, in: id) != nil, let name = server.households[id] else { return nil }
            return HouseholdDTO(id: id, name: name)
        }
    }

    func myHouseholds() async throws -> [HouseholdDTO] {
        try server.run("myHouseholds") {
            server.households.filter { server.role(user, in: $0.key) != nil }
                .map { HouseholdDTO(id: $0.key, name: $0.value) }
        }
    }

    func members(householdID: UUID) async throws -> [MemberDTO] {
        try server.run("members") {
            guard server.role(user, in: householdID) != nil else { return [] }
            return (server.members[householdID] ?? [:]).map {
                MemberDTO(userID: $0.key, role: $0.value, displayName: server.names[householdID]?[$0.key])
            }
        }
    }

    func setDisplayName(_ name: String, householdID: UUID, userID: UUID) async throws {
        try server.run("setDisplayName") {
            guard userID == user, server.role(user, in: householdID) != nil else { throw RemoteError.forbidden("rls") }
            server.setName(name, householdID, user)
        }
    }

    func createInvite(householdID: UUID, role: HouseholdRole) async throws -> String {
        try server.run("createInvite") {
            guard server.role(user, in: householdID) == .owner else { throw RemoteError.forbidden("rls") }
            let token = UUID().uuidString
            server.addInvite(token, householdID, role)
            return token
        }
    }

    func acceptInvite(token: String) async throws -> UUID {
        try server.run("acceptInvite") { try server.useInvite(token, by: user) }
    }

    func leave(householdID: UUID, userID: UUID) async throws {
        try server.run("leave") {
            guard userID == user || server.role(user, in: householdID) == .owner else { throw RemoteError.forbidden("rls") }
            try server.removeMember(userID, householdID)
        }
    }

    func dogs(householdID: UUID) async throws -> [RemoteDogDTO] {
        try server.run("dogs") {
            guard server.role(user, in: householdID) != nil else { return [] }
            return server.dogs.values.filter { $0.dto.householdID == householdID }.map {
                RemoteDogDTO(id: $0.dto.id, name: $0.dto.name, breedKind: $0.dto.breedKind,
                             breedLabel: $0.dto.breedLabel, deletedAt: $0.deletedAt)
            }
        }
    }

    func upsertDog(_ dog: DogDTO) async throws {
        try server.run("upsertDog") {
            try server.requireWriter(user, dog.householdID)
            server.putDog(dog)
        }
    }

    func tombstoneDog(id: UUID, at date: Date) async throws {
        try server.run("tombstoneDog") { server.deleteDog(id, date) }
    }

    func upsertWalk(_ walk: WalkSummaryDTO) async throws {
        try server.run("upsertWalk") {
            try server.requireWriter(user, walk.householdID)
            try server.putWalk(walk, by: user)
        }
    }

    func replaceParticipants(walkID: UUID, with dogs: [WalkDogDTO]) async throws {
        try server.run("replaceParticipants") { try server.setParticipants(walkID, dogs) }
    }

    func tombstoneWalk(id: UUID, at date: Date) async throws {
        try server.run("tombstoneWalk") { server.deleteWalk(id, date) }
    }

    func walks(householdID: UUID, changedSince since: Date?) async throws -> [RemoteWalkDTO] {
        try server.run("walks") {
            guard server.role(user, in: householdID) != nil else { return [] }
            return server.walks.values
                .filter { walk in
                    walk.summary.householdID == householdID && (since.map { walk.updatedAt > $0 } ?? true)
                }
                .map { walk in
                    RemoteWalkDTO(id: walk.summary.id, authorID: walk.authorID, revision: walk.revision,
                                  source: walk.summary.source, quality: walk.summary.quality,
                                  startedAt: walk.summary.startedAt, endedAt: walk.summary.endedAt,
                                  confirmedSeconds: walk.summary.confirmedSeconds,
                                  recordedPathMeters: walk.summary.recordedPathMeters,
                                  correctedAt: walk.summary.correctedAt, updatedAt: walk.updatedAt,
                                  deletedAt: walk.deletedAt,
                                  dogs: walk.dogs.map { .init(dogID: $0.dogID, dogNameSnapshot: $0.dogNameSnapshot) })
                }
        }
    }
}
