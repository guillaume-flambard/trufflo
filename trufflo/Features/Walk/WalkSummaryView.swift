import SwiftUI
import SwiftData

/// The post-walk summary (PRD "Bilan"): what was recorded, read back from the
/// store, plus the one thing the live screen deliberately does not offer, a note.
///
/// Content is warm and opaque here: the person has stopped walking, the map is a
/// picture of what happened, and reading is allowed again. Nothing is recomputed:
/// duration, distance and quality are the stored values.
@MainActor
struct WalkSummaryView: View {
    /// The celebration when the person ends the walk; the plain résumé of the
    /// board's "Fin automatique" when it ended on its own (interrupted, then
    /// finished with what was recorded).
    enum Style { case celebration, saved }

    @Environment(\.modelContext) private var context

    @Query private var matches: [WalkRecord]
    @Query private var participants: [WalkDogRecord]
    @Query private var points: [TrackPointRecord]
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]

    @State private var note = ""
    @State private var title = ""
    @State private var mood: WalkMood?
    @State private var showEditor = false
    @State private var celebrate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLoadedNote = false
    @State private var saveError: String?
    /// A finished walk is framed once and never chases the camera afterwards.
    @State private var isFollowingTrack = false

    private let walkID: UUID
    private let style: Style
    private let onDone: () -> Void

    init(walkID: UUID, style: Style = .celebration, onDone: @escaping () -> Void) {
        self.walkID = walkID
        self.style = style
        self.onDone = onDone
        _matches = Query(filter: #Predicate<WalkRecord> { $0.id == walkID })
        _participants = Query(filter: #Predicate<WalkDogRecord> { $0.walkID == walkID })
        _points = Query(filter: #Predicate<TrackPointRecord> { $0.walkID == walkID },
                        sort: \.sequence, order: .forward)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let walk = matches.first {
                    switch style {
                    case .celebration: content(for: walk)
                    case .saved: savedContent(for: walk)
                    }
                } else {
                    TruffloNotice(title: "Cette balade n'existe plus",
                                  message: "Elle a été retirée de cet appareil.",
                                  actionTitle: "Fermer") { onDone() }
                }
            }
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // The media runs under the bar; the button floats over it in glass.
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEditor) {
                if let walk = matches.first { WalkDetailsEditor(walk: walk) }
            }
            .navigationDestination(for: WalkRoute.self) { WalkDetailView(walkID: $0.id) }
            .tint(Color.truffloForest)
            .alert("Note non enregistrée", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - Content

    /// The end of a balade, as the 2026-10-07 board draws it: a burst of
    /// confetti, the dog, the mood (or "Super balade !"), the two figures, the
    /// note as a quote to write, then Enregistrer, Modifier, Partager.
    private func content(for walk: WalkRecord) -> some View {
        let shown = presentation(of: walk)
        return ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    TruffloConfetti(isOn: celebrate && !reduceMotion)
                        .frame(height: 220)
                        .allowsHitTesting(false)
                    if let photo = shown.leadPhoto {
                        TruffloDogPortrait(name: shown.leadName ?? "", photoData: photo, diameter: 132, aimsAtAnimal: true)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                            .scaleEffect(celebrate || reduceMotion ? 1 : 0.6)
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(Color.truffloForest)
                            .frame(width: 132, height: 132)
                            .background(Color(red: 0.86, green: 0.93, blue: 0.89), in: Circle())
                    }
                }
                .padding(.top, 40)

                VStack(spacing: 6) {
                    Text("\((mood ?? .great).label) !")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.truffloForest)
                    Text("\(shown.title), \(walk.endedAt.map(WalkFormatting.relativeDayAndTime) ?? "")")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.truffloSlate)
                }

                HStack(spacing: 0) {
                    figure(WalkFormatting.minutes(walk.confirmedSeconds), "Durée")
                    if let meters = walk.recordedPathMeters {
                        Rectangle().fill(Color.truffloForest.opacity(0.12)).frame(width: 1, height: 44)
                        figure(WalkFormatting.distance(meters), "Distance")
                    }
                }
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                MoodChips(selection: $mood)
                    .frame(maxWidth: .infinity, alignment: .center)

                TextField("“ Un mot sur la balade… ”", text: $note, axis: .vertical)
                    .font(.system(size: 15).italic())
                    .multilineTextAlignment(.center)
                    .lineLimit(1...5)
                    .padding(14)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityIdentifier("walk.summary.note")

                Text(WalkFormatting.quality(walk.quality) + (qualityHint(for: walk.quality).map { ". " + $0 } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button(action: saveAndClose) {
                        Label("Enregistrer", systemImage: "plus")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color.truffloForest)
                    .accessibilityIdentifier("walk.summary.done")

                    Button { showEditor = true } label: {
                        Text("Modifier")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.truffloForest)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(Capsule().strokeBorder(Color.truffloForest.opacity(0.5), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: shareText(walk, shown)) {
                        Text("Partager la balade")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.truffloForest)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, TruffloTheme.Spacing.large)
            .padding(.bottom, TruffloTheme.Spacing.large)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            LinearGradient(colors: [Color(red: 0.89, green: 0.95, blue: 0.91), Color.truffloSand],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .onAppear {
            guard !hasLoadedNote else { return }
            note = walk.note
            title = walk.title
            mood = walk.mood
            hasLoadedNote = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { celebrate = true }
        }
        .sensoryFeedback(.success, trigger: celebrate)
    }

    /// "Fin automatique (résumé)" of the 2026-10-07 board: the tracé, the dog
    /// over it, "Balade enregistrée !", four figures, and "Voir les détails".
    /// No confetti: the walk did not end by the person's choice.
    private func savedContent(for walk: WalkRecord) -> some View {
        let shown = presentation(of: walk)
        let lead = dogs.first { dog in participants.contains { $0.dogID == dog.id } }
        var figures: [(icon: String?, value: String, label: String)] = [
            (nil, WalkFormatting.minutes(walk.confirmedSeconds), "Durée"),
        ]
        if let meters = walk.recordedPathMeters {
            figures.append((nil, WalkFormatting.distance(meters), "Distance"))
            if walk.confirmedSeconds >= 60 {
                let kmh = (meters / 1000) / (walk.confirmedSeconds / 3600)
                figures.append(("gauge.with.needle",
                                "\(kmh.formatted(.number.precision(.fractionLength(1)).locale(TruffloLocale.french))) km/h",
                                "Allure moy."))
            }
            if let kcal = CalorieEstimate.kcal(weightKg: lead?.weightKg, meters: meters, size: lead?.size) {
                figures.append(("flame", "\(kcal) kcal", "Estimation"))
            }
        }
        return ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    if let route = shown.route(maxPoints: WalkPresentation.picturePoints) {
                        TruffloRouteMap(points: route, cacheKey: "\(walk.id.uuidString)-\(walk.revision)-summary",
                                        isVivid: true)
                    } else {
                        Color(red: 0.89, green: 0.94, blue: 0.90)
                    }
                }
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.top, 8)

                Group {
                    if let photo = shown.leadPhoto {
                        TruffloDogPortrait(name: shown.leadName ?? "", photoData: photo, diameter: 112, aimsAtAnimal: true)
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.truffloForest)
                            .frame(width: 112, height: 112)
                            .background(Color(red: 0.86, green: 0.93, blue: 0.89), in: Circle())
                    }
                }
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, -56)

                Text("Balade enregistrée !")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.truffloForest)
                    .padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)
                Text(walk.endedAt.map { "\(WalkFormatting.relativeDay($0).capitalizedFirst) · \(WalkFormatting.time($0))" } ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.truffloSlate)
                    .padding(.top, 2)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(Array(figures.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            if let icon = item.icon {
                                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.truffloForest)
                            }
                            VStack(spacing: 2) {
                                Text(item.value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                                    .foregroundStyle(Color.truffloForest)
                                Text(item.label).font(.system(size: 12)).foregroundStyle(Color.truffloSlate)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 18)

                if let hint = qualityHint(for: walk.quality) {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                }

                NavigationLink(value: WalkRoute(id: walk.id)) {
                    Text("Voir les détails")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.truffloForest, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("walk.saved.details")

                Button("Fermer", action: onDone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.truffloForest)
                    .frame(minHeight: 44)
                    .padding(.top, 6)
                    .accessibilityIdentifier("walk.summary.done")
            }
            .padding(.horizontal, TruffloTheme.Spacing.large)
            .padding(.bottom, TruffloTheme.Spacing.large)
        }
        .background(Color.truffloSand.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: hasLoadedNote)
        .onAppear { hasLoadedNote = true }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color.truffloForest)
            Text(label).font(.system(size: 13)).foregroundStyle(Color.truffloSlate)
        }
        .frame(maxWidth: .infinity)
    }

    private func shareText(_ walk: WalkRecord, _ shown: WalkPresentation) -> String {
        var parts = ["Balade avec \(shown.title) : \(WalkFormatting.minutes(walk.confirmedSeconds))"]
        if let meters = walk.recordedPathMeters { parts.append(WalkFormatting.distance(meters)) }
        return parts.joined(separator: ", ") + ". Avec Trufflo."
    }

    /// Names, face and tracé of the balade, by the rules every screen shares.
    private func presentation(of walk: WalkRecord) -> WalkPresentation {
        WalkPresentation(walk: walk, participants: participants, dogs: dogs, points: points)
    }

    // MARK: - Data

    /// Canonical microcopy: a gap is named as a gap, never papered over.
    private func qualityHint(for quality: WalkQuality) -> String? {
        switch quality {
        case .gpsPartial: "Une partie du tracé n'a pas été mesurée."
        case .unavailable: "Aucun point n'a été accepté. La durée seule est conservée."
        case .gpsRecorded, .manual: nil
        }
    }

    // MARK: - Actions

    /// Writes the note only when it changed, then closes. A failed write keeps the
    /// screen open: the walk itself is already saved, only the note is at stake.
    private func saveAndClose() {
        guard let walk = matches.first else {
            onDone()
            return
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == walk.note && cleanTitle == walk.title && mood == walk.mood {
            onDone()
            return
        }
        do {
            try JournalRepository(context: context).updateWalkDetails(walk.id, title: title, mood: mood, note: note)
            onDone()
        } catch WalkError.titleTooLong {
            saveError = "Le titre doit contenir au maximum 80 caractères."
        } catch WalkError.noteTooLong {
            saveError = "La note doit contenir au maximum 500 caractères."
        } catch {
            saveError = "La note n'a pas été enregistrée. La balade, elle, est bien conservée."
        }
    }
}
