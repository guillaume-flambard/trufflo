import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
public final class ActiveWalkViewModel: ObservableObject {
    @Published public private(set) var walkID: UUID?
    @Published public private(set) var phase: WalkPhase = .recording
    @Published public private(set) var confirmedSeconds: TimeInterval = 0
    @Published public private(set) var distanceMeters: Double?
    @Published public private(set) var isLocationActive: Bool = false
    /// Fixes are arriving but of poor quality. A threshold on the reported
    /// horizontal accuracy, never on distance: the screen says the signal is weak,
    /// it does not downgrade a measurement the accumulator already accepted.
    @Published public private(set) var isSignalWeak: Bool = false
    @Published public private(set) var dogNames: [String] = []
    @Published public var errorMessage: String?
    /// Why the live session was cut short, as one sentence for the screen's
    /// temporary notice. Not an error: the walk is still there, paused by the
    /// system rather than by the person, and it can be resumed or finished.
    @Published public private(set) var interruptionNotice: String?
    /// The walk that `finish()` just closed. The view switches to the summary on
    /// it, because `walkID` is released on success and cannot carry it.
    @Published public private(set) var finishedWalkID: UUID?
    /// The path recorded so far, for display only. The distance the app shows is
    /// the accumulator's, never a length computed from these coordinates.
    @Published public private(set) var trackPoints: [TrackCoordinate] = []
    /// Set when a start was refused before any session existed. The view turns
    /// it into the alert the spec asks for: a reason, a way into Settings when
    /// that can help, and manual entry either way.
    @Published public private(set) var startBlock: LocationBlock?
    /// Why a live session was interrupted, so the interrupted screen can offer
    /// the same exits instead of a generic message.
    @Published public private(set) var interruptionBlock: LocationBlock?

    private let modelContainer: ModelContainer
    private let locationProvider: LocationProviding
    private let accessibilityAnnouncer: AccessibilityAnnouncing
    private let settingsOpener: SettingsOpening
    private let clock = ContinuousClock()
    private let checkpointInterval: TimeInterval = 15
    private let fixBatchSize = 3

    private var trackWriter: TrackWriter?
    private var ticker: AnyCancellable?
    private var pendingFixes: [LocationFix] = []
    private var generation = 0
    private var runStart: ContinuousClock.Instant?
    private var accumulatedBeforeRun: TimeInterval = 0
    private var lastCheckpointSeconds: TimeInterval = 0

    public init(
        modelContainer: ModelContainer,
        locationProvider: LocationProviding = CoreLocationProvider(),
        accessibilityAnnouncer: AccessibilityAnnouncing = SystemAccessibilityAnnouncer(),
        settingsOpener: SettingsOpening = SystemSettingsOpener()
    ) {
        self.modelContainer = modelContainer
        self.locationProvider = locationProvider
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.settingsOpener = settingsOpener
        self.trackWriter = TrackWriter(modelContainer: modelContainer)
        installHandler()
    }

    // MARK: - Session lifecycle

    public func startSession(dogIDs: [UUID]) {
        guard walkID == nil else { return }
        startBlock = nil
        switch locationProvider.authorization {
        case .denied:
            startBlock = .permissionDenied
            return
        case .restricted:
            startBlock = .permissionRestricted
            return
        case .notDetermined:
            Task { await locationProvider.requestWhenInUse() }
        case .authorizedWhenInUse, .authorizedAlways:
            break
        }
        // A permission the user holds is not a working service. Without this
        // check the session opened, the clock ran and no fix ever arrived, so
        // the walk looked started and recorded nothing.
        guard locationProvider.servicesAvailable else {
            startBlock = .servicesUnavailable
            return
        }
        let repository = JournalRepository(context: ModelContext(modelContainer))
        do {
            adopt(try repository.startGpsSession(dogIDs: dogIDs), repository: repository)
            accessibilityAnnouncer.announce("Balade en cours")
        } catch {
            errorMessage = "Impossible de démarrer la balade."
        }
    }

    /// The single wording the walk screen uses for the signal. Derived here rather
    /// than in the view so the screen cannot show a colour without a word beside it.
    public var signalState: TruffloGPSIndicator.State {
        if phase == .paused { return .paused }
        if phase == .interrupted { return .interrupted }
        if isLocationActive { return isSignalWeak ? .weak : .strong }
        return .searching
    }

    /// Opens the app's Settings page. Used by the blocked-start alert and by the
    /// interrupted screen, where a refusal is the one cause Settings can fix.
    public func openSettings() {
        settingsOpener.openAppSettings()
    }

    public func dismissStartBlock() {
        startBlock = nil
    }

    public func resumeExisting(walkID: UUID) {
        guard self.walkID == nil else { return }
        let repository = JournalRepository(context: ModelContext(modelContainer))
        guard let walk = repository.walk(id: walkID) else { return }
        adopt(walk, repository: repository)
    }

    public func pause() {
        guard let walkID, phase == .recording else { return }
        endRun()
        let repository = JournalRepository(context: ModelContext(modelContainer))
        do {
            try repository.pauseWalk(walkID, confirmedSeconds: confirmedSeconds)
            phase = .paused
            accumulatedBeforeRun = confirmedSeconds
            lastCheckpointSeconds = confirmedSeconds
            sendPendingFixes()
            writeCheckpoint()
            Task { await locationProvider.stop() }
            accessibilityAnnouncer.announce("Balade en pause")
        } catch {
            errorMessage = "Erreur lors de la mise en pause."
            beginRun()
        }
    }

    public func resume() {
        guard let walkID, phase == .paused || phase == .interrupted else { return }
        let repository = JournalRepository(context: ModelContext(modelContainer))
        do {
            try repository.resumeWalk(walkID)
            phase = .recording
            interruptionNotice = nil
            beginRun()
            let writer = trackWriter
            let provider = locationProvider
            Task {
                if let writer { try? await writer.breakSegment(for: walkID) }
                await provider.start()
            }
            accessibilityAnnouncer.announce("Balade reprise")
        } catch {
            errorMessage = "Erreur lors de la reprise."
        }
    }

    public func finish() async {
        guard let walkID, let trackWriter else { return }
        guard phase != .completed else { return }
        let finalSeconds = elapsedSeconds()
        confirmedSeconds = finalSeconds
        endRun()
        generation += 1
        installHandler()
        let batch = pendingFixes
        pendingFixes.removeAll()
        await locationProvider.stop()
        do {
            if !batch.isEmpty {
                _ = try await trackWriter.appendFixes(batch, to: walkID)
            }
            // The note is not written here: the live screen has no field for it.
            // It is added on the summary screen, after the walk is saved.
            _ = try await trackWriter.finish(confirmedSeconds: finalSeconds, note: "", for: walkID)
            phase = .completed
            // Released on success, so a second tap on "Terminer" is a no-op.
            // Leaving the identifier set made the second call reach the writer,
            // which refused an already closed session and reported an error
            // over a walk that had just been saved.
            self.walkID = nil
            finishedWalkID = walkID
            interruptionBlock = nil
            interruptionNotice = nil
            trackPoints = []
            isSignalWeak = false
            accumulatedBeforeRun = 0
            lastCheckpointSeconds = 0
            accessibilityAnnouncer.announce("Balade terminée")
        } catch {
            errorMessage = "Erreur lors de la clôture de la balade."
        }
    }

    // MARK: - Monotonic clock

    private func beginRun() {
        accumulatedBeforeRun = confirmedSeconds
        lastCheckpointSeconds = confirmedSeconds
        runStart = clock.now
        ticker?.cancel()
        ticker = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func endRun() {
        confirmedSeconds = elapsedSeconds()
        runStart = nil
        ticker?.cancel()
        ticker = nil
    }

    private func elapsedSeconds() -> TimeInterval {
        guard let runStart else { return confirmedSeconds }
        return accumulatedBeforeRun + Self.seconds(runStart.duration(to: clock.now))
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }

    private func tick() {
        guard phase == .recording, runStart != nil else { return }
        confirmedSeconds = elapsedSeconds()
        guard confirmedSeconds - lastCheckpointSeconds >= checkpointInterval else { return }
        lastCheckpointSeconds = confirmedSeconds
        writeCheckpoint()
    }

    // MARK: - Location pipeline

    private func installHandler() {
        let expected = generation
        locationProvider.setHandler { [weak self] event in
            guard let self, self.generation == expected else { return }
            switch event {
            case .stateChanged(let state):
                self.applyServiceState(state)
            case .fix(let fix):
                self.handleFix(fix)
            }
        }
    }

    private func applyServiceState(_ state: LocationServiceState) {
        // A signal only counts as active while the walk is actually recording.
        // Without the phase in this condition, a fix that arrives just after a
        // pause lit the lamp back up although nothing was being collected.
        isLocationActive = (state == .active) && phase == .recording
        let block: LocationBlock?
        switch state {
        case .denied: block = .permissionDenied
        case .restricted: block = .permissionRestricted
        case .unavailable: block = .servicesUnavailable
        default: block = nil
        }
        guard let block else { return }
        // A walk that never started has no block to interrupt: report it as the
        // reason the start was refused instead.
        guard walkID != nil else {
            startBlock = block
            return
        }
        interruptSession(cause: block)
    }

    /// Reported accuracy at which the screen calls the signal weak. Between the
    /// accumulator's 35 m ceiling and this value the fix is stored but the signal
    /// is worth flagging; a technical hypothesis to calibrate in the field, not a
    /// dog-health rule.
    private let weakSignalAccuracy: Double = 20

    private func handleFix(_ fix: LocationFix) {
        guard phase == .recording, walkID != nil else { return }
        isSignalWeak = fix.horizontalAccuracy > weakSignalAccuracy
        pendingFixes.append(fix)
        guard pendingFixes.count >= fixBatchSize else { return }
        sendPendingFixes()
    }

    private func sendPendingFixes() {
        guard let walkID, let trackWriter, !pendingFixes.isEmpty else {
            pendingFixes.removeAll()
            return
        }
        let batch = pendingFixes
        pendingFixes.removeAll()
        let expected = generation
        Task {
            do {
                let summary = try await trackWriter.appendFixes(batch, to: walkID)
                guard self.generation == expected else { return }
                self.distanceMeters = summary.recordedPathMeters
                self.trackPoints.append(contentsOf: summary.insertedPoints.map {
                    TrackCoordinate(segment: $0.segment, latitude: $0.latitude, longitude: $0.longitude)
                })
            } catch {
                return
            }
        }
    }

    private func writeCheckpoint() {
        guard let walkID, let trackWriter else { return }
        let seconds = confirmedSeconds
        Task { _ = try? await trackWriter.checkpoint(confirmedSeconds: seconds, for: walkID) }
    }

    // MARK: - Interruption

    private func interruptSession(cause: LocationBlock) {
        guard let walkID else { return }
        guard phase == .recording || phase == .paused else { return }
        if phase == .recording { endRun() }
        let repository = JournalRepository(context: ModelContext(modelContainer))
        do {
            try repository.interruptWalk(walkID, confirmedSeconds: confirmedSeconds)
        } catch {
            interruptionBlock = cause
            errorMessage = cause.message
            Task { await locationProvider.stop() }
            return
        }
        phase = .interrupted
        interruptionBlock = cause
        accumulatedBeforeRun = confirmedSeconds
        lastCheckpointSeconds = confirmedSeconds
        generation += 1
        installHandler()
        sendPendingFixes()
        writeCheckpoint()
        Task { await locationProvider.stop() }
        // The copy names the actual cause: a walk cut short by disabled location
        // services must not claim the permission was withdrawn. It goes to the
        // screen's temporary notice, not to a modal: an interruption is a state
        // the person recovers from, not an error they have to acknowledge.
        interruptionNotice = switch cause {
        case .permissionDenied:
            "La localisation n'est plus autorisée."
        case .permissionRestricted:
            "La localisation est restreinte sur cet appareil."
        case .servicesUnavailable:
            "La localisation est désactivée sur cet appareil."
        }
        accessibilityAnnouncer.announce("Balade interrompue")
    }

    private func adopt(_ walk: WalkRecord, repository: JournalRepository) {
        generation += 1
        installHandler()
        walkID = walk.id
        phase = walk.phase
        confirmedSeconds = walk.confirmedSeconds
        accumulatedBeforeRun = walk.confirmedSeconds
        lastCheckpointSeconds = walk.confirmedSeconds
        distanceMeters = walk.recordedPathMeters
        dogNames = repository.participants(walkID: walk.id).map(\.dogNameSnapshot)
        pendingFixes.removeAll()
        let writer = trackWriter
        let expected = generation
        // A resumed session opens on an already recorded path: read it back so the
        // map shows the whole walk and not only what arrives after the relaunch.
        Task { [weak self] in
            guard let writer, let stored = try? await writer.storedPoints(for: walk.id) else { return }
            guard self?.generation == expected else { return }
            self?.trackPoints = stored.map {
                TrackCoordinate(segment: $0.segment, latitude: $0.latitude, longitude: $0.longitude)
            }
        }
        guard walk.phase == .recording else { return }
        beginRun()
        Task { await locationProvider.start() }
    }
}
