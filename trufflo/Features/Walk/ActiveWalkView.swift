import AVFoundation
import CoreLocation
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
    @State private var isLocked = false
    @State private var announces = false
    @State private var lastAnnouncedKm = 0
    /// Ended from the interrupted state (app killed, signal or permission lost):
    /// the walk did not end by the person's choice, so the plain résumé shows
    /// instead of the celebration.
    @State private var endedWhileInterrupted = false
    /// Guidance to the planned place of the day, when there is one.
    @Query(sort: \PlannedWalkRecord.date) private var plans: [PlannedWalkRecord]
    @State private var guide: WalkRouteGuide.Route?
    @State private var guideStep = 0
    @State private var showsGuide = true
    @State private var askedRoute = false
    /// Dogs of the foyer that share their position during their own balade.
    /// Empty in production until the foyer live position is built and decided;
    /// filled only by `--demo-proximity` for the board capture.
    @State private var nearbyDogs: [NearbyDog] = []
    @State private var acknowledgedDogs: Set<UUID> = []
    private let speech = AVSpeechSynthesizer()
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
                WalkSummaryView(walkID: summaryWalkID, style: endedWhileInterrupted ? .saved : .celebration) { dismiss() }
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
                endedWhileInterrupted = isInterrupted
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

    /// The live walk of the 2026-10-07 board: the map is the screen; the three
    /// figures in a white bar at the top; round map controls on the right; at
    /// the bottom a large pause / resume, the lock, and the stop.
    ///
    /// Stopping never happens in one tap (product rule 5): while recording, the
    /// stop button pauses and asks; in pause it asks. Locked, the screen ignores
    /// touches until it is unlocked.
    private var liveScreen: some View {
        ZStack(alignment: .top) {
            TruffloTrackMap(points: viewModel.trackPoints,
                            isLive: viewModel.phase == .recording,
                            showsMarkers: true,
                            isFollowing: $isFollowingTrack,
                            guideRoute: activeGuide?.path ?? [],
                            destination: guidePlan.flatMap(Self.destination(of:)),
                            nearbyDog: proximityAlert.map { CLLocationCoordinate2D(latitude: $0.dog.latitude, longitude: $0.dog.longitude) })
                .ignoresSafeArea()
                .accessibilityIdentifier("walk.map")

            if viewModel.phase != .recording {
                // Paused or interrupted: the map dims, the state reads in the middle.
                Color.black.opacity(0.28).ignoresSafeArea().allowsHitTesting(false)
                Label(isInterrupted ? "Interrompue" : "En pause", systemImage: isInterrupted ? "exclamationmark.triangle.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 10) {
                if let banner = guideBanner {
                    banner
                } else {
                    statsBar
                }
                HStack(alignment: .top) {
                    TruffloGPSIndicator(viewModel.signalState)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.9), in: Capsule())
                    Spacer(minLength: 0)
                    VStack(spacing: 12) {
                        mapButton("chevron.down", label: "Réduire la balade", identifier: "walk.minimize") { dismiss() }
                        mapButton(announces ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                  label: announces ? "Annonces vocales activées" : "Annonces vocales coupées",
                                  identifier: "walk.voice") { announces.toggle() }
                        mapButton("scope", label: "Voir tout le tracé", identifier: "walk.map.overview") {
                            isFollowingTrack = false
                        }
                        mapButton(isFollowingTrack ? "location.fill" : "location",
                                  label: isFollowingTrack ? "Suivi automatique actif" : "Recentrer le tracé",
                                  identifier: "walk.map.recentre") { isFollowingTrack = true }
                    }
                }
                if let notice {
                    interruptionToast(notice)
                }
                Spacer(minLength: 0)
                if let alert = proximityAlert {
                    proximityCard(meters: alert.roundedMeters, dogID: alert.dog.id)
                } else {
                    if guideBanner != nil { statsBar }
                    bottomControls
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if isLocked { lockScreen }
        }
        .onChange(of: viewModel.distanceMeters) { _, meters in announceIfNeeded(meters) }
        .onChange(of: viewModel.trackPoints.count) { _, _ in followGuide() }
        .task { seedProximityDemo() }
    }

    // MARK: - Guidance and proximity

    /// The plan the walk heads to: today's, with a place on the map.
    private var guidePlan: PlannedWalkRecord? {
        plans.first { plan in
            plan.latitude != nil && plan.longitude != nil
                && plan.date > Date.now.addingTimeInterval(-3 * 3600)
                && plan.date < Date.now.addingTimeInterval(24 * 3600)
        }
    }

    private static func destination(of plan: PlannedWalkRecord) -> CLLocationCoordinate2D? {
        guard let latitude = plan.latitude, let longitude = plan.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var activeGuide: WalkRouteGuide.Route? { showsGuide ? guide : nil }

    /// Asks MapKit once for the route, on the first fix; then moves the banner
    /// along as manoeuvres are reached.
    private func followGuide() {
        guard let last = viewModel.trackPoints.last else { return }
        if !askedRoute, let plan = guidePlan, let end = Self.destination(of: plan) {
            askedRoute = true
            let start = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
            Task { guide = await WalkRouteGuide.route(from: start, to: end) }
        }
        if let guide {
            guideStep = Guidance.advance(from: guideStep, steps: guide.steps,
                                         latitude: last.latitude, longitude: last.longitude)
        }
    }

    /// "À 200 m / Prenez l'allée à droite", the green banner of the board.
    private var guideBanner: AnyView? {
        guard let guide = activeGuide, viewModel.phase == .recording,
              guideStep < guide.steps.count, let last = viewModel.trackPoints.last else { return nil }
        let step = guide.steps[guideStep]
        let meters = Guidance.meters(to: step, latitude: last.latitude, longitude: last.longitude)
        return AnyView(
            HStack(spacing: 14) {
                Image(systemName: Guidance.symbol(for: step.instruction))
                    .font(.system(size: 30, weight: .bold))
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Guidance.distanceLabel(meters))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(step.instruction)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button { withAnimation { showsGuide = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Masquer le guidage")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.truffloForest, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("walk.guide")
        )
    }

    private var proximityAlert: (dog: NearbyDog, roundedMeters: Int)? {
        guard viewModel.phase == .recording, let last = viewModel.trackPoints.last else { return nil }
        return Proximity.alert(for: nearbyDogs, latitude: last.latitude, longitude: last.longitude,
                               acknowledged: acknowledgedDogs)
    }

    /// "Autre chien à proximité", the bottom card of the board. A rounded
    /// distance, never the other person's exact position.
    private func proximityCard(meters: Int, dogID: UUID) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color(red: 0.93, green: 0.3, blue: 0.18), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Autre chien à proximité")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                    Text("Un chien de votre foyer est à ~ \(meters) m.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.truffloSlate)
                }
                Spacer(minLength: 0)
            }
            Button {
                acknowledgedDogs.insert(dogID)
            } label: {
                Text("Compris").font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.truffloForest)
            .accessibilityIdentifier("walk.nearby.ok")
            Button {
                isFollowingTrack = false
                acknowledgedDogs.insert(dogID)
            } label: {
                Text("Voir sur la carte").font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.truffloForest)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color(red: 0.89, green: 0.94, blue: 0.90), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        .accessibilityIdentifier("walk.nearby")
    }

    /// `--uitesting --demo-proximity`: one dog of the foyer 30 m away from the
    /// first fix, to capture the board's alert. Never in a real session.
    private func seedProximityDemo() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"), arguments.contains("--demo-proximity") else { return }
        Task {
            while viewModel.trackPoints.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            if let first = viewModel.trackPoints.last {
                nearbyDogs = [NearbyDog(id: UUID(), latitude: first.latitude + 0.00027, longitude: first.longitude)]
            }
        }
    }

    /// Duration, distance and speed, the white bar of the board.
    private var statsBar: some View {
        HStack(spacing: 0) {
            stat(WalkFormatting.clock(viewModel.confirmedSeconds), "Durée", identifier: "walk.timer")
            stat(viewModel.distanceMeters.map { ($0 / 1000).formatted(.number.precision(.fractionLength(2)).locale(TruffloLocale.french)) } ?? "Non mesurée",
                 viewModel.distanceMeters == nil ? "Distance" : "km", identifier: "walk.distance",
                 spoken: WalkFormatting.distance(viewModel.distanceMeters))
            stat(speedText, "km/h", identifier: "walk.speed")
        }
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }

    private func stat(_ value: String, _ unit: String, identifier: String, spoken: String? = nil) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(spoken ?? value)
                .accessibilityIdentifier(identifier)
            Text(unit)
                .font(.system(size: 12))
                .foregroundStyle(Color.truffloSlate)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private var speedText: String {
        guard let meters = viewModel.distanceMeters, viewModel.confirmedSeconds >= 30 else { return "0,0" }
        let kmh = (meters / 1000) / (viewModel.confirmedSeconds / 3600)
        return kmh.formatted(.number.precision(.fractionLength(1)).locale(TruffloLocale.french))
    }

    private func mapButton(_ icon: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.truffloForest)
                .frame(width: 46, height: 46)
                .background(Color.white, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// Pause or resume, large and green; the lock; the stop, red.
    @ViewBuilder
    private var bottomControls: some View {
        switch viewModel.phase {
        case .completed, .discarded:
            HStack(spacing: 8) {
                ProgressView().tint(Color.truffloForest)
                Text("Enregistrement…").font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.white.opacity(0.9), in: Capsule())
        default:
            VStack(spacing: 10) {
                if isInterrupted, viewModel.interruptionBlock?.offersSettings == true {
                    Button("Ouvrir les réglages") { viewModel.openSettings() }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.truffloForest)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Color.white, in: Capsule())
                        .accessibilityIdentifier("walk.interrupted.settings")
                }
                HStack {
                    roundControl(viewModel.phase == .recording ? "pause.fill" : "play.fill",
                                 size: 72, fill: Color.truffloForest, tint: .white,
                                 label: viewModel.phase == .recording ? "Mettre en pause"
                                     : (isInterrupted ? "Reprendre à partir de maintenant" : "Reprendre la balade"),
                                 identifier: viewModel.phase == .recording ? "walk.pause" : "walk.resume") {
                        if viewModel.phase == .recording { viewModel.pause() } else { viewModel.resume() }
                    }
                    Spacer()
                    roundControl("lock.fill", size: 46, fill: .white, tint: Color.truffloCharcoal,
                                 label: "Verrouiller l'écran", identifier: "walk.lock") {
                        withAnimation(.easeInOut(duration: 0.2)) { isLocked = true }
                    }
                    Spacer()
                    roundControl("stop.fill", size: 72, fill: .white, tint: Color(red: 0.88, green: 0.16, blue: 0.14),
                                 label: isInterrupted ? "Terminer avec les données enregistrées" : "Terminer la balade",
                                 identifier: viewModel.phase == .recording ? "walk.stop" : "walk.finish") {
                        // Rule 5: never ends in one tap; while recording it pauses first.
                        if viewModel.phase == .recording { viewModel.pause() }
                        showFinishConfirmation = true
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func roundControl(_ icon: String, size: CGFloat, fill: Color, tint: Color, label: String,
                              identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.phase)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// Locked: nothing reacts to a pocket touch; a long press unlocks.
    private var lockScreen: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "lock.fill").font(.system(size: 34)).foregroundStyle(.white)
                Text("Écran verrouillé").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(viewModel.phase == .recording ? "Balade en cours…" : "Balade en pause")
                    .font(.system(size: 16)).foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("Appui long pour déverrouiller").font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                Spacer().frame(height: 30)
                Image(systemName: viewModel.phase == .recording ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.truffloForest, in: Circle())
                    .padding(.bottom, 24)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) {
            withAnimation(.easeInOut(duration: 0.2)) { isLocked = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Écran verrouillé")
        .accessibilityHint("Appui long pour déverrouiller")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isLocked = false }
        .accessibilityIdentifier("walk.locked")
    }

    /// Says the distance aloud at each new kilometre when voice is on.
    private func announceIfNeeded(_ meters: Double?) {
        guard announces, let meters else { return }
        let km = Int(meters / 1000)
        guard km > lastAnnouncedKm else { return }
        lastAnnouncedKm = km
        let text = "\(km) kilomètre\(km > 1 ? "s" : ""), \(WalkFormatting.minutes(viewModel.confirmedSeconds))"
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        speech.speak(utterance)
    }

    /// Temporary, small, and gone after eight seconds. The signal word
    /// "Interrompue" and the Settings link stay on the surface, so missing the
    /// toast costs nothing but the sentence.
    private func interruptionToast(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.truffloCharcoal)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, TruffloTheme.Spacing.medium)
            .padding(.vertical, 10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
