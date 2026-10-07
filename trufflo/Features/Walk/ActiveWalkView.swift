import SwiftUI
import SwiftData

/// The live walk. One surface, one primary action.
///
/// The map is the screen. Over it sit exactly three things: a chevron to minimise,
/// a circle to recentre, and one glass control surface at the bottom that holds the
/// title, the signal word, the two measurements and the action for the current
/// state. The person is walking and probably holding a leash, so nothing here asks
/// to be read or decided beyond "pause" or "resume".
///
/// - Recording: Pause. Finishing is not offered while the walk is running.
/// - Paused: Resume (dominant) and Finish (quiet, confirmed).
/// - Interrupted: same pair, the signal reads "Interrompue", and a temporary notice
///   says what is kept. Settings is offered only when a withdrawn permission is
///   the cause, because it is the one cause Settings can repair.
/// - Finished: the summary replaces the screen, and the note is written there.
///
/// Content is warm; controls are glass. One material for the surface, one for the
/// two round controls, and no card inside a card.
@MainActor
public struct ActiveWalkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: ActiveWalkViewModel
    @Query private var dogs: [DogRecord]
    @State private var showFinishConfirmation = false
    @State private var showManualEntry = false
    /// Presentation mirror of `viewModel.startBlock`. The model stays the source
    /// of truth for *what* blocked the start; the alert owns only its own
    /// visibility. Writing back to the model from the dismissal closure would
    /// publish during a view update, which SwiftUI reports as undefined
    /// behaviour (same class as E-026).
    @State private var blockedAlert: LocationBlock?
    /// Whether the map camera is still following the recorded path. Owned here so
    /// the recentre control can sit outside the map.
    @State private var isFollowingTrack = true
    /// The temporary notice shown under the chevron after an interruption. The
    /// token re-creates the toast so its six-second timer restarts each time.
    @State private var notice: String?
    @State private var noticeToken = 0
    /// Set once `finish()` has saved the walk: the summary takes the screen over.
    @State private var summaryWalkID: UUID?
    private let dogIDsToStart: [UUID]
    private let walkIDToResume: UUID?

    private static let keptDataSentence = "Données conservées jusqu'au dernier point enregistré."

    public init(modelContainer: ModelContainer, dogIDs: [UUID] = []) {
        _viewModel = StateObject(wrappedValue: ActiveWalkViewModel(modelContainer: modelContainer))
        dogIDsToStart = dogIDs
        walkIDToResume = nil
    }

    public init(modelContainer: ModelContainer, existingWalkID: UUID) {
        _viewModel = StateObject(wrappedValue: ActiveWalkViewModel(modelContainer: modelContainer))
        dogIDsToStart = []
        walkIDToResume = existingWalkID
    }

    public var body: some View {
        ZStack {
            if let summaryWalkID {
                WalkSummaryView(walkID: summaryWalkID) { dismiss() }
                    .transition(.opacity)
            } else {
                liveScreen
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: summaryWalkID)
        .tint(Color.truffloForest)
        .task {
            if let walkIDToResume {
                viewModel.resumeExisting(walkID: walkIDToResume)
            } else if !dogIDsToStart.isEmpty {
                viewModel.startSession(dogIDs: dogIDsToStart)
            }
        }
        .onChange(of: viewModel.startBlock) { _, block in
            blockedAlert = block
        }
        .onChange(of: viewModel.phase) { _, phase in
            if phase == .interrupted { showInterruptionNotice() } else { hideNotice() }
        }
        .onChange(of: viewModel.interruptionNotice) { _, cause in
            // The cause can land in the same turn as the phase or just after it:
            // refresh the notice either way so it never shows without its cause.
            if cause != nil, viewModel.phase == .interrupted { showInterruptionNotice() }
        }
        .onChange(of: viewModel.finishedWalkID) { _, finished in
            guard let finished else { return }
            summaryWalkID = finished
        }
        .sheet(isPresented: $showManualEntry) {
            ManualWalkFormView(dogs: dogs)
        }
        // Ending a walk is always a deliberate second tap. The sheet names the
        // interrupted case explicitly: finishing there saves what was recorded
        // and claims nothing about what was lost.
        .confirmationDialog(finishTitle, isPresented: $showFinishConfirmation, titleVisibility: .visible) {
            Button(finishButtonTitle) {
                Task { await viewModel.finish() }
            }
            Button("Continuer") {}
        } message: {
            Text(finishMessage)
        }
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // A refused start is not an error string: the spec asks for the
        // reason, a route into Settings when that can actually fix it, and
        // manual entry either way, so a walk stays possible without GPS.
        .alert(
            blockedAlert?.message ?? "",
            isPresented: Binding(
                get: { blockedAlert != nil },
                set: { if !$0 { blockedAlert = nil } }
            )
        ) {
            if blockedAlert?.offersSettings == true {
                Button("Ouvrir les réglages") {
                    viewModel.openSettings()
                    clearBlockedAlert()
                }
                .accessibilityIdentifier("walk.blocked.settings")
                Button("Ajouter manuellement") {
                    clearBlockedAlert()
                    showManualEntry = true
                }
                .accessibilityIdentifier("walk.blocked.manual")
                Button("Annuler") { clearBlockedAlert() }
            } else {
                Button("Ajouter manuellement") {
                    clearBlockedAlert()
                    showManualEntry = true
                }
                .accessibilityIdentifier("walk.blocked.manual")
                Button("OK") { clearBlockedAlert() }
            }
        }
    }

    // MARK: - Live screen

    private var liveScreen: some View {
        ZStack(alignment: .top) {
            // Rank 1: the map, never reduced and never covered by a panel.
            TruffloTrackMap(points: viewModel.trackPoints,
                            isLive: viewModel.phase == .recording,
                            showsMarkers: true,
                            isFollowing: $isFollowingTrack)
                .ignoresSafeArea()
                .accessibilityIdentifier("walk.map")

            GlassEffectContainer(spacing: TruffloTheme.Spacing.small) {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    TruffloRoundAction(systemImage: "chevron.down",
                                       label: "Réduire la balade",
                                       identifier: "walk.minimize") {
                        dismiss()
                    }
                    Spacer(minLength: 0)
                }

                if let notice {
                    interruptionToast(notice)
                        .padding(.top, TruffloTheme.Spacing.xSmall)
                }

                Spacer(minLength: TruffloTheme.Spacing.medium)

                if !viewModel.trackPoints.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        recentreControl
                    }
                    .padding(.bottom, TruffloTheme.Spacing.xSmall)
                }

                controlSurface
            }
            .padding(.horizontal, TruffloTheme.Spacing.small)
            .padding(.top, TruffloTheme.Spacing.xSmall)
            .padding(.bottom, TruffloTheme.Spacing.xSmall)
            }
        }
    }

    /// The one control surface: title and signal, the two measurements, then the
    /// action row for the current state. Strong sand, because it carries numbers
    /// over a busy map.
    private var controlSurface: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(walkTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.truffloForest)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("walk.title")

                Spacer(minLength: TruffloTheme.Spacing.xSmall)

                TruffloGPSIndicator(viewModel.signalState)
            }

            TruffloWalkMetrics(
                durationText: WalkFormatting.clock(viewModel.confirmedSeconds),
                distanceText: WalkFormatting.distance(viewModel.distanceMeters),
                distanceIsMeasured: viewModel.distanceMeters != nil
            )

            actions
        }
        .padding(TruffloTheme.Spacing.medium)
        .truffloGlass(strength: .strong)
    }

    /// One primary per state, always the last row. Finish is never shown while
    /// recording, and never as a primary.
    @ViewBuilder
    private var actions: some View {
        switch viewModel.phase {
        case .recording:
            TruffloPrimaryAction("Pause", systemImage: "pause.fill",
                                 accessibilityLabel: "Mettre en pause",
                                 identifier: "walk.pause") {
                viewModel.pause()
            }

        case .paused, .interrupted:
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                TruffloPrimaryAction("Reprendre", systemImage: "play.fill",
                                     accessibilityLabel: isInterrupted
                                        ? "Reprendre à partir de maintenant"
                                        : "Reprendre la balade",
                                     identifier: "walk.resume") {
                    viewModel.resume()
                }
                TruffloQuietAction("Terminer", systemImage: "stop.fill",
                                   accessibilityLabel: isInterrupted
                                      ? "Terminer avec les données enregistrées"
                                      : "Terminer la balade",
                                   identifier: "walk.finish") {
                    showFinishConfirmation = true
                }
            }
            if isInterrupted, viewModel.interruptionBlock?.offersSettings == true {
                Button("Ouvrir les réglages") {
                    viewModel.openSettings()
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.truffloForest)
                .frame(maxWidth: .infinity, minHeight: 44)
                .truffloTap()
                .accessibilityIdentifier("walk.interrupted.settings")
            }

        case .completed, .discarded:
            // The summary is about to take over; the row shows the save rather
            // than an action that no longer applies.
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                ProgressView()
                    .tint(Color.truffloForest)
                Text("Enregistrement…")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.truffloForest)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
    }

    /// Small circular control. The filled arrow means following, the outline one
    /// means the camera was moved away, and the spoken label states it.
    private var recentreControl: some View {
        TruffloRoundAction(systemImage: isFollowingTrack ? "location.fill" : "location",
                           label: isFollowingTrack ? "Suivi automatique actif" : "Recentrer le parcours",
                           identifier: "walk.map.recentre",
                           tint: Color.truffloForest) {
            isFollowingTrack = true
        }
    }

    /// Temporary, small, and gone after eight seconds. The signal word
    /// "Interrompue" and the Settings link stay on the surface, so missing the
    /// toast costs nothing but the sentence.
    private func interruptionToast(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.truffloForest)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, TruffloTheme.Spacing.medium)
            .padding(.vertical, 10)
            .truffloGlassControl(strength: .strong)
            .accessibilityLabel(text)
            .accessibilityIdentifier("walk.notice")
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .id(noticeToken)
            .task {
                // Eight seconds: long enough to read two sentences at a glance,
                // short enough that it is a notice and not a banner.
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                hideNotice()
            }
    }

    // MARK: - State

    private var isInterrupted: Bool { viewModel.phase == .interrupted }

    private var walkTitle: String {
        let names = viewModel.dogNames
        guard !names.isEmpty else { return "Balade" }
        let list = names.formatted(.list(type: .and).locale(TruffloLocale.french))
        return "Balade avec \(list)"
    }

    private var finishTitle: String {
        isInterrupted ? "Terminer avec les données enregistrées ?" : "Terminer et enregistrer la balade ?"
    }

    private var finishButtonTitle: String {
        isInterrupted ? "Terminer avec les données enregistrées" : "Terminer la balade"
    }

    private var finishMessage: String {
        isInterrupted
            ? "Aucune durée n'a été ajoutée depuis l'interruption. La balade est conservée jusqu'au dernier point enregistré."
            : "La durée et le tracé GPS de votre balade seront ajoutés à votre journal."
    }

    private func showInterruptionNotice() {
        let text = [viewModel.interruptionNotice, Self.keptDataSentence]
            .compactMap { $0 }
            .joined(separator: " ")
        guard text != notice else { return }
        noticeToken += 1
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            notice = text
        }
    }

    private func hideNotice() {
        guard notice != nil else { return }
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) {
            notice = nil
        }
    }

    private func clearBlockedAlert() {
        blockedAlert = nil
        viewModel.dismissStartBlock()
    }
}
