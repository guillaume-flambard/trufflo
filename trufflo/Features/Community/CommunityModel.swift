import Foundation
import Observation

/// The screen-facing side of the community walk events (lot C): who this
/// person is, what the zone offers, what they asked for. Everything shown comes
/// from the server's last answer; nothing is kept that the server did not say.
@MainActor
@Observable
final class CommunityModel {
    enum Phase: Equatable { case loading, needsProfile, ready, failed(String) }

    private(set) var phase = Phase.loading
    private(set) var isBusy = false
    private(set) var profile: CommunityProfileDTO?
    private(set) var zones: [CommunityZone] = []
    private(set) var events: [WalkEventDTO] = []
    private(set) var myEvents: [WalkEventDTO] = []
    private(set) var myDogs: [CommunityDogDTO] = []
    private(set) var isOrganizer = false
    private(set) var userID: UUID?
    /// Moves after every action and reload, so a screen that reads something the
    /// model does not keep (an event's participants) knows to read it again.
    private(set) var revision = 0
    /// A refusal or a failure the person can read, shown once.
    var errorMessage: String?

    private let remote: any CommunityRemote

    init(remote: any CommunityRemote) { self.remote = remote }

    var zoneName: String? { zones.first { $0.id == profile?.zoneID }?.name }

    func event(_ id: UUID) -> WalkEventDTO? {
        myEvents.first { $0.id == id } ?? events.first { $0.id == id }
    }

    // MARK: Loading

    func refresh() async {
        do {
            userID = try await remote.currentUserID()
            zones = try await remote.zones()
            guard let profile = try await remote.myProfile() else {
                self.profile = nil
                phase = .needsProfile
                return
            }
            self.profile = profile
            async let upcoming = remote.events(zoneID: profile.zoneID)
            async let mine = remote.myEvents()
            async let dogs = remote.myDogs()
            async let organizer = remote.isOrganizer(zoneID: profile.zoneID)
            (events, myEvents, myDogs, isOrganizer) = try await (upcoming, mine, dogs, organizer)
            phase = .ready
            revision += 1
        } catch CommunityError.noProfile {
            profile = nil
            phase = .needsProfile
        } catch {
            if phase == .loading || phase == .needsProfile { phase = .failed(Self.message(for: error)) }
            else { errorMessage = Self.message(for: error) }
        }
    }

    // MARK: Actions. Each one asks, then reads again what the server now holds.

    func saveProfile(displayName: String, zoneID: String, adultDeclared: Bool) async {
        await act { try await self.remote.saveProfile(displayName: displayName, zoneID: zoneID, adultDeclared: adultDeclared) }
    }

    func requestToJoin(_ eventID: UUID, dogIDs: [UUID]) async {
        await act { try await self.remote.requestToJoin(eventID: eventID, dogIDs: dogIDs) }
    }

    func withdraw(_ eventID: UUID) async { await act { try await self.remote.withdraw(eventID: eventID) } }

    func declareAttendance(_ eventID: UUID, attended: Bool) async {
        await act { try await self.remote.declareAttendance(eventID: eventID, attended: attended) }
    }

    func addDog(name: String, breedLabel: String = "", publicNote: String = "") async -> UUID? {
        guard let userID else { return nil }
        let dog = CommunityDogDTO(id: UUID(), ownerID: userID,
                                  name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  breedLabel: breedLabel, publicNote: publicNote)
        var saved = false
        await act { try await self.remote.saveDog(dog); saved = true }
        return saved ? dog.id : nil
    }

    func removeDog(_ id: UUID) async { await act { try await self.remote.deleteDog(id: id) } }

    func createEvent(_ draft: WalkEventDraft) async -> UUID? {
        guard let zone = profile?.zoneID else { return nil }
        var created: UUID?
        await act { created = try await self.remote.createEvent(draft, zoneID: zone) }
        return created
    }

    func decide(_ eventID: UUID, userID: UUID, accept: Bool) async {
        await act { try await self.remote.decide(eventID: eventID, userID: userID, accept: accept) }
    }

    func updateEvent(_ eventID: UUID, startsAt: Date, meetingPoint: String) async {
        await act { try await self.remote.updateEvent(eventID: eventID, startsAt: startsAt,
                                                      meetingPoint: meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func cancelEvent(_ eventID: UUID) async { await act { try await self.remote.cancelEvent(eventID: eventID) } }

    func report(_ target: ReportTarget, id: UUID, reason: ReportReason, detail: String) async -> Bool {
        var done = false
        await act { try await self.remote.report(target, id: id, reason: reason, detail: detail); done = true }
        return done
    }

    func block(_ userID: UUID) async { await act { try await self.remote.block(userID: userID) } }
    func unblock(_ userID: UUID) async { await act { try await self.remote.unblock(userID: userID) } }

    // Reads that belong to one event, not kept in the model.
    func participants(of eventID: UUID) async -> [EventParticipantDTO] {
        (try? await remote.participants(eventID: eventID)) ?? []
    }
    func updates(of eventID: UUID) async -> [EventUpdateDTO] {
        (try? await remote.updates(eventID: eventID)) ?? []
    }

    private func act(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
            await refresh()
        } catch {
            errorMessage = Self.message(for: error)
            await refresh()
        }
    }

    static func message(for error: Error) -> String {
        guard let error = error as? CommunityError else {
            return "Le serveur n'a pas répondu. Réessayez."
        }
        switch error {
        case .invalid(let text): return text
        case .noProfile: return "Créez d'abord votre profil."
        case .notAllowed: return "Action non autorisée."
        case .eventFull: return "La sortie est complète."
        case .eventGone: return "Cette sortie n'est plus disponible."
        case .blocked: return "Vous ne pouvez pas rejoindre cette sortie."
        case .network: return "Le serveur n'a pas répondu. Réessayez."
        }
    }
}
