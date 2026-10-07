#if DEBUG
import Foundation

/// An in-memory community server that applies the rules of ADR 0010: who sees
/// what, the capacity check, blocks in both directions, inscription apart from
/// attendance. It is the reference the client is tested against and what the
/// demo mode runs on, until the real server exists. Never compiled into a
/// release build, so production shows no outing it did not receive.
final class InMemoryCommunityServer: @unchecked Sendable {
    struct Outing {
        var dto: OutingDTO
        var updates: [OutingUpdateDTO] = []
    }
    struct Participation {
        var status: ParticipationStatus
        var dogIDs: [UUID]
        var attended: Bool?
    }
    struct Report: Equatable {
        var reporter: UUID
        var target: ReportTarget
        var targetID: UUID
        var reason: ReportReason
    }

    private let lock = NSLock()
    var clock: () -> Date = { .now }
    private(set) var zones: [CommunityZone] = []
    private var closedZones: Set<String> = []
    private(set) var profiles: [UUID: CommunityProfileDTO] = [:]
    private(set) var dogs: [UUID: CommunityDogDTO] = [:]
    private(set) var organizers: [UUID: Set<String>] = [:]
    private(set) var outings: [UUID: Outing] = [:]
    private(set) var participations: [UUID: [UUID: Participation]] = [:]
    private(set) var reports: [Report] = []
    private(set) var blocks: Set<[UUID]> = []
    private(set) var calls: [String] = []
    var failure: CommunityError?

    func client(_ user: UUID) -> InMemoryCommunityRemote { InMemoryCommunityRemote(server: self, user: user) }

    // MARK: Setup, as the migrations and the moderator would do it

    func addZone(_ zone: CommunityZone, open: Bool = true) {
        zones.append(zone)
        if !open { closedZones.insert(zone.id) }
    }
    func makeOrganizer(_ user: UUID, in zone: String) { organizers[user, default: []].insert(zone) }
    func suspend(_ user: UUID) { profiles[user]?.suspended = true }

    // MARK: Rules

    fileprivate func run<T>(_ name: String, _ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        calls.append(name)
        if let failure { throw failure }
        return try body()
    }

    private func valid(_ user: UUID) throws -> CommunityProfileDTO {
        guard let profile = profiles[user], !profile.suspended else { throw CommunityError.noProfile }
        return profile
    }

    private func areBlocked(_ a: UUID, _ b: UUID) -> Bool { blocks.contains([a, b]) || blocks.contains([b, a]) }

    fileprivate func openZones() -> [CommunityZone] { zones.filter { !closedZones.contains($0.id) } }

    fileprivate func visibleOutings(to user: UUID, zone: String) throws -> [OutingDTO] {
        let me = try valid(user)
        guard me.zoneID == zone, !closedZones.contains(zone) else { return [] }
        let since = clock().addingTimeInterval(-86400)
        return outings.values.map(\.dto)
            .filter { $0.zoneID == zone && $0.status == .published && $0.startsAt >= since && !areBlocked($0.organizerID, user) }
            .map { withMine($0, user) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private func withMine(_ dto: OutingDTO, _ user: UUID) -> OutingDTO {
        var out = dto
        out.myStatus = participations[dto.id]?[user]?.status
        out.myAttended = participations[dto.id]?[user]?.attended
        let accepted = participations[dto.id]?.values.filter { $0.status == .accepted } ?? []
        out.humansAccepted = accepted.count
        out.dogsAccepted = accepted.reduce(0) { $0 + $1.dogIDs.count }
        return out
    }

    fileprivate func mine(_ user: UUID) throws -> [OutingDTO] {
        _ = try valid(user)
        return outings.values.map(\.dto)
            .filter { $0.organizerID == user || participations[$0.id]?[user] != nil }
            .map { withMine($0, user) }
            .sorted { $0.startsAt > $1.startsAt }
    }

    fileprivate func request(_ user: UUID, _ outingID: UUID, _ dogIDs: [UUID]) throws {
        let me = try valid(user)
        guard let outing = outings[outingID]?.dto else { throw CommunityError.outingGone }
        guard outing.status == .published, outing.startsAt > clock(), outing.zoneID == me.zoneID else { throw CommunityError.outingGone }
        guard !areBlocked(outing.organizerID, user) else { throw CommunityError.blocked }
        guard outing.organizerID != user else { throw CommunityError.notAllowed }
        guard dogIDs.allSatisfy({ dogs[$0]?.ownerID == user }) else { throw CommunityError.notAllowed }
        if let existing = participations[outingID]?[user]?.status, existing == .requested || existing == .accepted { return }
        participations[outingID, default: [:]][user] = Participation(status: .requested, dogIDs: dogIDs, attended: nil)
    }

    fileprivate func decide(_ organizer: UUID, _ outingID: UUID, _ user: UUID, accept: Bool) throws {
        _ = try valid(organizer)
        guard let outing = outings[outingID]?.dto, outing.organizerID == organizer else { throw CommunityError.notAllowed }
        guard outing.status == .published else { throw CommunityError.outingGone }
        guard var request = participations[outingID]?[user], request.status == .requested else { throw CommunityError.notAllowed }
        if accept {
            let current = withMine(outing, organizer)
            if current.humansAccepted + 1 > outing.humanCapacity || current.dogsAccepted + request.dogIDs.count > outing.dogCapacity {
                throw CommunityError.outingFull
            }
        }
        request.status = accept ? .accepted : .declined
        participations[outingID]?[user] = request
    }

    fileprivate func withdraw(_ user: UUID, _ outingID: UUID) throws {
        _ = try valid(user)
        participations[outingID]?[user]?.status = .withdrawn
    }

    fileprivate func attendance(_ user: UUID, _ outingID: UUID, _ attended: Bool) throws {
        _ = try valid(user)
        guard let outing = outings[outingID]?.dto, outing.endsAt <= clock(),
              participations[outingID]?[user]?.status == .accepted else { throw CommunityError.notAllowed }
        participations[outingID]?[user]?.attended = attended
    }

    fileprivate func create(_ user: UUID, _ draft: OutingDraft, _ zone: String) throws -> UUID {
        let me = try valid(user)
        guard organizers[user]?.contains(zone) == true, me.zoneID == zone else { throw CommunityError.notAllowed }
        let id = UUID()
        outings[id] = Outing(dto: OutingDTO(
            id: id, organizerID: user, organizerName: me.displayName, zoneID: zone, startsAt: draft.startsAt,
            durationMinutes: draft.durationMinutes, meetingPoint: draft.meetingPoint, rules: draft.rules,
            humanCapacity: draft.humanCapacity, dogCapacity: draft.dogCapacity, humansAccepted: 0, dogsAccepted: 0,
            status: .published, myStatus: nil))
        return id
    }

    fileprivate func update(_ user: UUID, _ outingID: UUID, startsAt: Date, meetingPoint: String) throws {
        guard var outing = outings[outingID], outing.dto.organizerID == user, outing.dto.status == .published else { throw CommunityError.notAllowed }
        let now = clock()
        if startsAt != outing.dto.startsAt {
            outing.updates.append(OutingUpdateDTO(id: UUID(), outingID: outingID, kind: .time,
                                                previous: outing.dto.startsAt.formatted(), current: startsAt.formatted(), createdAt: now))
            outing.dto.startsAt = startsAt
        }
        if meetingPoint != outing.dto.meetingPoint {
            outing.updates.append(OutingUpdateDTO(id: UUID(), outingID: outingID, kind: .place,
                                                previous: outing.dto.meetingPoint, current: meetingPoint, createdAt: now))
            outing.dto.meetingPoint = meetingPoint
        }
        outings[outingID] = outing
    }

    fileprivate func cancel(_ user: UUID, _ outingID: UUID) throws {
        guard var outing = outings[outingID], outing.dto.organizerID == user else { throw CommunityError.notAllowed }
        outing.dto.status = .cancelled
        outing.updates.append(OutingUpdateDTO(id: UUID(), outingID: outingID, kind: .cancelled, previous: "", current: "", createdAt: clock()))
        outings[outingID] = outing
    }

    fileprivate func participantList(_ user: UUID, _ outingID: UUID) throws -> [OutingParticipantDTO] {
        _ = try valid(user)
        guard let outing = outings[outingID]?.dto else { throw CommunityError.outingGone }
        let all = participations[outingID] ?? [:]
        let isOrganizer = outing.organizerID == user
        guard isOrganizer || all[user]?.status == .accepted else { throw CommunityError.notAllowed }
        return all.compactMap { id, part -> OutingParticipantDTO? in
            guard isOrganizer || part.status == .accepted else { return nil }
            guard let profile = profiles[id] else { return nil }
            let names = part.dogIDs.compactMap { dogs[$0]?.name }.sorted()
            return OutingParticipantDTO(userID: id, displayName: profile.displayName, status: part.status,
                                       dogNames: names, attended: isOrganizer ? part.attended : nil)
        }.sorted { $0.displayName < $1.displayName }
    }

    fileprivate func updateList(_ user: UUID, _ outingID: UUID) throws -> [OutingUpdateDTO] {
        _ = try valid(user)
        guard let outing = outings[outingID] else { throw CommunityError.outingGone }
        guard outing.dto.organizerID == user || participations[outingID]?[user]?.status == .accepted
                || participations[outingID]?[user]?.status == .requested else { throw CommunityError.notAllowed }
        return outing.updates.sorted { $0.createdAt > $1.createdAt }
    }

    fileprivate func saveProfile(_ user: UUID, _ name: String, _ zone: String, _ adult: Bool) throws {
        guard adult else { throw CommunityError.invalid("Le pilote est réservé aux adultes.") }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(clean.count) else { throw CommunityError.invalid("Un nom de 1 à 40 caractères.") }
        guard zones.contains(where: { $0.id == zone }), !closedZones.contains(zone) else { throw CommunityError.invalid("Cette zone n'est pas ouverte.") }
        if profiles[user]?.suspended == true { throw CommunityError.noProfile }
        let since = profiles[user]?.adultDeclaredAt ?? clock()
        profiles[user] = CommunityProfileDTO(userID: user, displayName: clean, zoneID: zone, adultDeclaredAt: since)
    }

    fileprivate func put(_ dog: CommunityDogDTO, by user: UUID) throws {
        _ = try valid(user)
        guard dog.ownerID == user, (1...40).contains(dog.name.count), dog.publicNote.count <= 200,
              dog.breedLabel.count <= 80 else { throw CommunityError.invalid("Ce chien n'est pas valide.") }
        dogs[dog.id] = dog
    }

    fileprivate func remove(dog id: UUID, by user: UUID) throws {
        guard dogs[id]?.ownerID == user else { throw CommunityError.notAllowed }
        dogs[id] = nil
    }

    fileprivate func file(_ report: Report) throws {
        _ = try valid(report.reporter)
        reports.append(report)
    }

    fileprivate func setBlock(_ blocker: UUID, _ blocked: UUID, _ on: Bool) throws {
        _ = try valid(blocker)
        if on { blocks.insert([blocker, blocked]) } else { blocks.remove([blocker, blocked]) }
    }

    fileprivate func blocked(by user: UUID) throws -> [BlockedPersonDTO] {
        _ = try valid(user)
        return blocks.filter { $0.first == user }.compactMap { pair in
            profiles[pair[1]].map { BlockedPersonDTO(userID: pair[1], displayName: $0.displayName) }
        }.sorted { $0.displayName < $1.displayName }
    }

    fileprivate func profile(of user: UUID) -> CommunityProfileDTO? {
        profiles[user].flatMap { $0.suspended ? nil : $0 }
    }
    fileprivate func dogsOf(_ user: UUID) -> [CommunityDogDTO] { dogs.values.filter { $0.ownerID == user }.sorted { $0.name < $1.name } }
    fileprivate func isOrganizerOf(_ user: UUID, _ zone: String) -> Bool { organizers[user]?.contains(zone) == true }
}

struct InMemoryCommunityRemote: CommunityRemote {
    let server: InMemoryCommunityServer
    let user: UUID

    func currentUserID() async throws -> UUID { user }
    func zones() async throws -> [CommunityZone] { try server.run("zones") { server.openZones() } }
    func myProfile() async throws -> CommunityProfileDTO? { try server.run("myProfile") { server.profile(of: user) } }
    func saveProfile(displayName: String, zoneID: String, adultDeclared: Bool) async throws {
        try server.run("saveProfile") { try server.saveProfile(user, displayName, zoneID, adultDeclared) }
    }
    func myDogs() async throws -> [CommunityDogDTO] { try server.run("myDogs") { server.dogsOf(user) } }
    func saveDog(_ dog: CommunityDogDTO) async throws { try server.run("saveDog") { try server.put(dog, by: user) } }
    func deleteDog(id: UUID) async throws { try server.run("deleteDog") { try server.remove(dog: id, by: user) } }
    func outings(zoneID: String) async throws -> [OutingDTO] { try server.run("outings") { try server.visibleOutings(to: user, zone: zoneID) } }
    func myOutings() async throws -> [OutingDTO] { try server.run("myOutings") { try server.mine(user) } }
    func participants(outingID: UUID) async throws -> [OutingParticipantDTO] {
        try server.run("participants") { try server.participantList(user, outingID) }
    }
    func updates(outingID: UUID) async throws -> [OutingUpdateDTO] { try server.run("updates") { try server.updateList(user, outingID) } }
    func requestToJoin(outingID: UUID, dogIDs: [UUID]) async throws {
        try server.run("requestToJoin") { try server.request(user, outingID, dogIDs) }
    }
    func withdraw(outingID: UUID) async throws { try server.run("withdraw") { try server.withdraw(user, outingID) } }
    func declareAttendance(outingID: UUID, attended: Bool) async throws {
        try server.run("declareAttendance") { try server.attendance(user, outingID, attended) }
    }
    func isOrganizer(zoneID: String) async throws -> Bool { try server.run("isOrganizer") { server.isOrganizerOf(user, zoneID) } }
    func createOuting(_ draft: OutingDraft, zoneID: String) async throws -> UUID {
        try server.run("createOuting") { try server.create(user, draft, zoneID) }
    }
    func decide(outingID: UUID, userID: UUID, accept: Bool) async throws {
        try server.run("decide") { try server.decide(user, outingID, userID, accept: accept) }
    }
    func updateOuting(outingID: UUID, startsAt: Date, meetingPoint: String) async throws {
        try server.run("updateOuting") { try server.update(user, outingID, startsAt: startsAt, meetingPoint: meetingPoint) }
    }
    func cancelOuting(outingID: UUID) async throws { try server.run("cancelOuting") { try server.cancel(user, outingID) } }
    func report(_ target: ReportTarget, id: UUID, reason: ReportReason, detail: String) async throws {
        try server.run("report") { try server.file(.init(reporter: user, target: target, targetID: id, reason: reason)) }
    }
    func block(userID: UUID) async throws { try server.run("block") { try server.setBlock(user, userID, true) } }
    func unblock(userID: UUID) async throws { try server.run("unblock") { try server.setBlock(user, userID, false) } }
    func blockedPeople() async throws -> [BlockedPersonDTO] { try server.run("blockedPeople") { try server.blocked(by: user) } }
}
#endif

#if DEBUG
/// `--demo-community` and friends: a zone with a few real-looking outings, to
/// look at the screens before the server exists. Names and places are made up
/// for the demo and never reach a release build.
extension InMemoryCommunityServer {
    enum DemoRequest {
        case none, newcomer, member, organizer

        init?(arguments: [String]) {
            if arguments.contains("--demo-community-organizer") { self = .organizer }
            else if arguments.contains("--demo-community-new") { self = .newcomer }
            else if arguments.contains("--demo-community") { self = .member }
            else { return nil }
        }
    }

    @MainActor
    static func demoModel(_ request: DemoRequest) -> CommunityModel {
        let server = InMemoryCommunityServer()
        let me = UUID(), lea = UUID(), marc = UUID(), sam = UUID()
        let zone = CommunityZone(id: "demo", name: "Zone de démonstration")
        server.addZone(zone)
        server.makeOrganizer(lea, in: zone.id)
        server.makeOrganizer(marc, in: zone.id)
        if request == .organizer { server.makeOrganizer(me, in: zone.id) }
        let adult = server.clock()
        func profile(_ id: UUID, _ name: String) {
            server.profiles[id] = CommunityProfileDTO(userID: id, displayName: name, zoneID: zone.id, adultDeclaredAt: adult)
        }
        profile(lea, "Léa"); profile(marc, "Marc"); profile(sam, "Sam")
        if request != .newcomer { profile(me, "Guillaume") }

        let calendar = Calendar.current
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let start = calendar.startOfDay(for: .now)
            let base = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        func outing(_ organizer: UUID, _ name: String, _ at: Date, _ minutes: Int, _ point: String, _ rules: String,
                   humans: Int, dogs: Int) -> UUID {
            let id = UUID()
            server.outings[id] = Outing(dto: OutingDTO(
                id: id, organizerID: organizer, organizerName: name, zoneID: zone.id, startsAt: at, durationMinutes: minutes,
                meetingPoint: point, rules: rules, humanCapacity: humans, dogCapacity: dogs,
                humansAccepted: 0, dogsAccepted: 0, status: .published, myStatus: nil))
            return id
        }
        let first = outing(lea, "Léa", day(2, 10), 60, "Entrée nord du parc", "Chiens en laisse près de l'étang. Sacs fournis.", humans: 6, dogs: 6)
        let second = outing(marc, "Marc", day(3, 9, 30), 90, "Parking du bois de la Fontaine", "Rythme tranquille, chiens sociables.", humans: 4, dogs: 4)
        _ = outing(lea, "Léa", day(9, 18), 45, "Place de la mairie", "", humans: 8, dogs: 8)

        if request != .newcomer {
            let dog = UUID()
            server.dogs[dog] = CommunityDogDTO(id: dog, ownerID: me, name: "Oslo")
            // Sam is already in the first one; I come to the second with Oslo.
            server.participations[first, default: [:]][sam] = Participation(status: .accepted, dogIDs: [], attended: nil)
            if request == .member {
                server.participations[second, default: [:]][me] = Participation(status: .requested, dogIDs: [dog], attended: nil)
                // A walk that ended an hour ago, where I was accepted: the attendance question.
                let over = outing(marc, "Marc", Date().addingTimeInterval(-3 * 3600), 120, "Quai de la Saône", "", humans: 5, dogs: 5)
                server.participations[over, default: [:]][me] = Participation(status: .accepted, dogIDs: [dog], attended: nil)
            }
        }
        if request == .organizer {
            let samDog = UUID()
            server.dogs[samDog] = CommunityDogDTO(id: samDog, ownerID: sam, name: "Pixel")
            let mine = outing(me, "Guillaume", day(4, 17), 60, "Place du marché", "Chiens sociables, en laisse jusqu'au parc.",
                             humans: 4, dogs: 3)
            server.participations[mine, default: [:]][sam] = Participation(status: .requested, dogIDs: [samDog], attended: nil)
            server.participations[mine, default: [:]][lea] = Participation(status: .accepted, dogIDs: [], attended: nil)
            let past = outing(me, "Guillaume", day(-2, 10), 60, "Bords de la rivière", "Rythme tranquille.", humans: 6, dogs: 6)
            server.participations[past, default: [:]][sam] = Participation(status: .accepted, dogIDs: [samDog], attended: true)
        }
        // Zone and identity are fixed for the demo: this device is « me ».
        return CommunityModel(remote: server.client(me))
    }
}
#endif
