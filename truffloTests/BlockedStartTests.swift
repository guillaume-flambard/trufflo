import Foundation
import SwiftData
import Testing
@testable import trufflo

private final class RecordingSettingsOpener: SettingsOpening, @unchecked Sendable {
    private(set) var openCount = 0
    func openAppSettings() {
        openCount += 1
    }
}

/// T36, T37 and T38 close the three blocking findings of the adversarial pass
/// (E-035). Each test names the finding it answers, because the reason these
/// existed is that the app looked like it was working: a walk could open with
/// no signal, or a second walk could appear beside an unfinished one, and
/// nothing on screen said so.
@MainActor
struct BlockedStartTests {
    private func makeHarness(
        authorization: LocationAuthorization = .authorizedWhenInUse,
        servicesEnabled: Bool = true
    ) throws -> (ModelContainer, JournalRepository, UUID, FakeLocationProvider,
                  RecordingSettingsOpener, ActiveWalkViewModel) {
        let container = try PersistenceFactory.make(inMemory: true)
        let repository = JournalRepository(context: container.mainContext)
        let dog = try repository.addDog(DogInput(name: "Nori", breedKind: "unknown", breedLabel: ""))
        let fake = FakeLocationProvider(authorization: authorization)
        fake.servicesEnabled = servicesEnabled
        let opener = RecordingSettingsOpener()
        let viewModel = ActiveWalkViewModel(
            modelContainer: container,
            locationProvider: fake,
            settingsOpener: opener
        )
        return (container, repository, dog.id, fake, opener, viewModel)
    }

    // MARK: - T37, location services switched off

    @Test("T37: with location services off, no session opens and no clock runs")
    func servicesOffCreatesNoSession() async throws {
        let (container, _, dogID, fake, _, viewModel) = try makeHarness(servicesEnabled: false)

        viewModel.startSession(dogIDs: [dogID])

        #expect(viewModel.walkID == nil)
        #expect(viewModel.phase == .recording)
        #expect(viewModel.confirmedSeconds == 0)
        #expect(viewModel.startBlock == .servicesUnavailable)

        try await Task.sleep(for: .milliseconds(1100))
        #expect(viewModel.confirmedSeconds == 0)
        #expect(fake.startCount == 0)

        let walks = try ModelContext(container).fetch(FetchDescriptor<WalkRecord>())
        #expect(walks.isEmpty)
    }

    @Test("T37: a disabled service is not blamed on the permission, and Settings is not offered")
    func servicesOffBlamesServicesNotPermission() throws {
        let (_, _, dogID, _, _, viewModel) = try makeHarness(servicesEnabled: false)

        viewModel.startSession(dogIDs: [dogID])

        let block = try #require(viewModel.startBlock)
        #expect(block == .servicesUnavailable)
        #expect(block.offersSettings == false)
        #expect(block.message.contains("désactivée"))
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.walkID == nil)
        _ = dogID
    }

    @Test("T37: services switched off mid-walk interrupt with the service copy, not a false revocation")
    func servicesOffMidWalkDoesNotClaimRevocation() async throws {
        let (container, _, dogID, fake, _, viewModel) = try makeHarness()

        viewModel.startSession(dogIDs: [dogID])
        try await Task.sleep(for: .milliseconds(1100))
        fake.setServicesEnabled(false)

        #expect(viewModel.phase == .interrupted)
        #expect(viewModel.interruptionBlock == .servicesUnavailable)

        // The cause feeds the screen's temporary notice, never a modal error.
        let message = try #require(viewModel.interruptionNotice)
        #expect(message.contains("désactivée"))
        #expect(!message.contains("n'est plus autorisée"))
        #expect(viewModel.errorMessage == nil)

        let stored = try #require(
            JournalRepository(context: ModelContext(container)).walk(id: viewModel.walkID ?? UUID())
        )
        #expect(stored.phase == .interrupted)
        #expect(stored.confirmedSeconds >= 1.0)
    }

    @Test("T37: a permission refusal mid-walk keeps the revocation copy and offers Settings")
    func revocationMidWalkOffersSettings() async throws {
        let (_, _, dogID, fake, _, viewModel) = try makeHarness()

        viewModel.startSession(dogIDs: [dogID])
        try await Task.sleep(for: .milliseconds(1100))
        fake.revoke()

        #expect(viewModel.phase == .interrupted)
        #expect(viewModel.interruptionBlock == .permissionDenied)
        #expect(viewModel.interruptionBlock?.offersSettings == true)
        #expect(viewModel.interruptionNotice?.contains("n'est plus autorisée") == true)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - T36, the refused start must be actionable

    @Test("T36: a refused start offers Settings, and asking for it reaches the opener")
    func refusedStartOpensSettings() throws {
        let (_, _, dogID, _, opener, viewModel) = try makeHarness(authorization: .denied)

        viewModel.startSession(dogIDs: [dogID])
        #expect(viewModel.startBlock == .permissionDenied)

        viewModel.openSettings()

        #expect(opener.openCount == 1)
    }

    @Test("T36: a device restriction is reported without a dead Settings route")
    func restrictionDoesNotOfferSettings() throws {
        let (_, _, dogID, _, opener, viewModel) = try makeHarness(authorization: .restricted)

        viewModel.startSession(dogIDs: [dogID])

        #expect(viewModel.startBlock == .permissionRestricted)
        #expect(viewModel.startBlock?.offersSettings == false)
        #expect(opener.openCount == 0)
    }

    @Test("T36: every blocked reason states something the user can act on")
    func everyBlockCarriesActionableCopy() {
        for block in [LocationBlock.permissionDenied, .permissionRestricted, .servicesUnavailable] {
            #expect(!block.message.isEmpty)
            #expect(block.message.first != nil)
        }
    }

    // MARK: - T38, one unfinished walk at a time

    @Test("T38: an interrupted walk is unfinished, so the repository hands it back")
    func interruptedWalkBlocksASecondSession() throws {
        let (container, repository, dogID, _, _, _) = try makeHarness()
        let first = try repository.startGpsSession(dogIDs: [dogID])
        try repository.checkpointWalk(first.id, confirmedSeconds: 12)
        try JournalRepository(context: container.mainContext).recoverInterruptedSessions()

        let check = JournalRepository(context: ModelContext(container))
        #expect(check.liveWalk()?.id == first.id)
        #expect(try check.walk(id: first.id)?.phase == .interrupted)

        let second = try check.startGpsSession(dogIDs: [dogID])

        #expect(second.id == first.id)
        let walks = try ModelContext(container).fetch(FetchDescriptor<WalkRecord>())
        #expect(walks.count == 1)
    }

    @Test("T38: starting while a walk is interrupted adopts it and never records")
    func startingDuringInterruptionAdoptsInsteadOfRecording() async throws {
        let (container, repository, dogID, fake, _, _) = try makeHarness()
        let first = try repository.startGpsSession(dogIDs: [dogID])
        try repository.checkpointWalk(first.id, confirmedSeconds: 30)
        try JournalRepository(context: container.mainContext).recoverInterruptedSessions()

        let viewModel = ActiveWalkViewModel(
            modelContainer: container,
            locationProvider: fake,
            settingsOpener: RecordingSettingsOpener()
        )
        viewModel.startSession(dogIDs: [dogID])

        #expect(viewModel.walkID == first.id)
        #expect(viewModel.phase == .interrupted)
        #expect(viewModel.confirmedSeconds == 30)
        // The sensor must stay off: resuming is an explicit choice.
        #expect(fake.startCount == 0)

        try await Task.sleep(for: .milliseconds(1100))
        #expect(viewModel.confirmedSeconds == 30)

        let walks = try ModelContext(container).fetch(FetchDescriptor<WalkRecord>())
        #expect(walks.count == 1)
    }

    @Test("T38: finishing releases the slot so the next start is a new walk")
    func finishingReleasesTheSlot() async throws {
        let (container, _, dogID, _, _, viewModel) = try makeHarness()
        viewModel.startSession(dogIDs: [dogID])
        let firstID = try #require(viewModel.walkID)

        await viewModel.finish()
        #expect(viewModel.phase == .completed)

        let check = JournalRepository(context: ModelContext(container))
        #expect(check.liveWalk() == nil)
        let second = try check.startGpsSession(dogIDs: [dogID])
        #expect(second.id != firstID)
    }
}