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
    @Published public private(set) var dogNames: [String] = []
    @Published public var note: String = ""
    @Published public var errorMessage: String?

    private let modelContainer: ModelContainer
    private let locationProvider: LocationProviding
    private let accessibilityAnnouncer: AccessibilityAnnouncing
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
        accessibilityAnnouncer: AccessibilityAnnouncing = SystemAccessibilityAnnouncer()
    ) {
        self.modelContainer = modelContainer
        self.locationProvider = locationProvider
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.trackWriter = TrackWriter(modelContainer: modelContainer)
        installHandler()
    }

    // MARK: - Session lifecycle

    public func startSession(dogIDs: [UUID]) {
        guard walkID == nil else { return }
        switch locationProvider.authorization {
        case .denied:
            errorMessage = "La localisation est refusée. Autorisez-la dans les réglages pour lancer une balade."
            return
        case .restricted:
            errorMessage = "La localisation est restreinte sur cet appareil."
            return
        case .notDetermined:
            Task { await locationProvider.requestWhenInUse() }
        case .authorizedWhenInUse, .authorizedAlways:
            break
        }
        let repository = JournalRepository(context: ModelContext(modelContainer))
        do {
            adopt(try repository.startGpsSession(dogIDs: dogIDs), repository: repository)
            accessibilityAnnouncer.announce("Balade en cours")
        } catch {
            errorMessage = "Impossible de démarrer la balade."
        }
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
            _ = try await trackWriter.finish(confirmedSeconds: finalSeconds, note: note, for: walkID)
            phase = .completed
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
        isLocationActive = (state == .active)
        guard state == .denied || state == .restricted else { return }
        interruptSession()
    }

    private func handleFix(_ fix: LocationFix) {
        guard phase == .recording, walkID != nil else { return }
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

    private func interruptSession() {
        guard let walkID else { return }
        guard phase == .recording || phase == .paused else { return }
        if phase == .recording { endRun() }
        let repository = JournalRepository(context: ModelContext(modelContainer))
        do {
            try repository.interruptWalk(walkID, confirmedSeconds: confirmedSeconds)
        } catch {
            errorMessage = "La localisation n'est plus disponible."
            Task { await locationProvider.stop() }
            return
        }
        phase = .interrupted
        accumulatedBeforeRun = confirmedSeconds
        lastCheckpointSeconds = confirmedSeconds
        generation += 1
        installHandler()
        sendPendingFixes()
        writeCheckpoint()
        Task { await locationProvider.stop() }
        errorMessage = "La localisation n'est plus autorisée. La balade est interrompue."
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
        guard walk.phase == .recording else { return }
        beginRun()
        Task { await locationProvider.start() }
    }
}
