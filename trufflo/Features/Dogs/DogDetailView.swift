import SwiftUI
import SwiftData

/// One profile: read it, correct it, remove it.
///
/// The screen reaches the profile through a `@Query` keyed on the navigation
/// UUID rather than by holding a `@Model`, so an edit refreshes in place and a
/// delete that happened elsewhere shows "gone" instead of a stale row.
@MainActor
struct DogDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var matches: [DogRecord]
    @Query private var participations: [WalkDogRecord]
    @Query(filter: #Predicate<WalkRecord> { $0.phaseRaw == "completed" }) private var finishedWalks: [WalkRecord]
    @Query private var routines: [RoutineRecord]

    @State private var showEdit = false
    @State private var showRoutine = false
    @State private var showHousehold = false
    @State private var showDeleteConfirmation = false
    @State private var storageError: String?

    init(dogID: UUID) {
        _matches = Query(filter: #Predicate<DogRecord> { $0.id == dogID })
        _routines = Query(filter: #Predicate<RoutineRecord> { $0.dogID == dogID })
    }

    var body: some View {
        Group {
            if let dog = matches.first {
                content(for: dog)
            } else {
                TruffloNotice(title: "Ce chien n'est plus sur cet iPhone", message: "Il a été retiré depuis un autre écran.", actionTitle: "Revenir à la liste") { dismiss() }
            }
        }
        // The title stays the dog's name, for the back menu, VoiceOver and the
        // edit journey, but is not drawn: the hero already says it, large.
        .navigationTitle(matches.first?.name ?? "Chien")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if matches.first != nil {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            }
            if matches.first != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifier") { showEdit = true }
                        .fontWeight(.semibold)
                        .truffloTap()
                        .accessibilityIdentifier("dog.edit")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .truffloScreen()
        .alert("Modification impossible", isPresented: Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )) {
            Button("Fermer", role: .cancel) {}
        } message: {
            Text(storageError ?? "")
        }
    }

    @ViewBuilder
    private func content(for dog: DogRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TruffloDogPortraitHero(name: dog.name, photoData: dog.photoData,
                                       subtitle: facts(of: dog), heightFactor: 0.5) {
                    if dog.photoData == nil {
                        Button {
                            showEdit = true
                        } label: {
                            // Same link as on Today, so the invitation reads the same twice.
                            Label("Ajouter une photo de \(dog.name)", systemImage: "camera")
                                .font(.truffloBodyHeavy)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.truffloForest)
                        .truffloTap()
                        .accessibilityIdentifier("dog.addPhoto")
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    let count = walkCount ?? 0
                    DogFactChips(dog: dog)

                    // The tiles of Today, so a figure reads the same on both screens.
                    HStack(spacing: 10) {
                        TruffloStatTile(systemImage: "figure.walk", tint: Color.truffloForest,
                                        value: "\(count)", label: count > 1 ? "balades" : "balade")
                        TruffloStatTile(systemImage: "clock", tint: Color(red: 0.85, green: 0.55, blue: 0.15),
                                        value: count == 0 ? "Pas encore" : WalkFormatting.minutes(recordedSeconds),
                                        label: "en tout", isSentence: count == 0)
                        TruffloStatTile(systemImage: "heart.fill", tint: Color(red: 0.24, green: 0.6, blue: 0.42),
                                        value: lastWalkDate.map { WalkFormatting.relativeDay($0).capitalizedFirst } ?? "Pas encore",
                                        label: "dernière balade", isSentence: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if !recentWalks.isEmpty {
                        Text("Dernières balades")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)
                        ForEach(recentWalks) { walk in
                            NavigationLink(value: WalkRoute(id: walk.id)) { TruffloLastWalkRow(walk: walk) }
                                .buttonStyle(.plain)
                        }
                    }

                    card(title: "Routine", systemImage: "repeat") { routineSection(for: dog) }

                    if !dog.preferencesNote.isEmpty {
                        card(title: "Préférences de balade", systemImage: "text.quote") {
                            Text(dog.preferencesNote)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.truffloCharcoal)
                            Text("Écrit par vous")
                                .font(.footnote)
                                .foregroundStyle(Color.truffloSlate)
                        }
                    }

                    HouseholdPrompt(place: .profile, dogName: dog.name) { showHousehold = true }

                    VStack(alignment: .leading, spacing: 4) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Supprimer \(dog.name)", systemImage: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.truffloDanger)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .truffloTap(.impact(weight: .medium))
                        .accessibilityIdentifier("dog.delete")
                        .accessibilityLabel("Supprimer \(dog.name)")
                        Text("\(dog.name) est retiré de cet iPhone. Les balades déjà enregistrées gardent son nom.")
                            .font(.footnote)
                            .foregroundStyle(Color.truffloSlate)
                    }
                    .truffloBoardCard()
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.top, TruffloTheme.Spacing.medium)
                .padding(.bottom, TruffloTheme.Spacing.xLarge)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollEdgeEffectHidden(true, for: .top)
        .sheet(isPresented: $showEdit) { DogFormView(profile: dog) }
        .sheet(isPresented: $showHousehold) { HouseholdView() }
        .sheet(isPresented: $showRoutine) {
            RoutineFormView(dogID: dog.id, dogName: dog.name, current: routines.first?.routine)
        }
        .confirmationDialog("Supprimer \(dog.name) ?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Supprimer \(dog.name)", role: .destructive) { delete(dogID: dog.id) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les balades déjà enregistrées gardent son nom.")
        }
    }

    /// Breed, age and sex, joined with commas: what the person declared and
    /// nothing else, no trait read from the walks. An unknown breed or an unset
    /// sex is the absence of a fact, not a fact to print.
    private func facts(of dog: DogRecord) -> String {
        [dog.breedKind != "unknown" ? dog.breedDescription : "",
         dog.ageDescription,
         dog.genderDescription == "Non renseigné" ? "" : dog.genderDescription.lowercased()]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// The chosen routine, or an invitation that makes clear the journal works
    /// without one. Paused, it stays visible and greyed, never deleted.
    @ViewBuilder
    private func routineSection(for dog: DogRecord) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            if let record = routines.first, let routine = record.routine {
                Text(routine.summary)
                    .font(.body)
                    .foregroundStyle(record.isPaused ? Color.truffloSlate : Color.truffloCharcoal)
                if record.isPaused {
                    Text("En pause : rien ne s'affiche sur Aujourd'hui.")
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                }
                HStack(spacing: TruffloTheme.Spacing.large) {
                    Button("Modifier") { showRoutine = true }
                        .truffloTap()
                        .accessibilityIdentifier("routine.edit")
                    Button(record.isPaused ? "Reprendre" : "Mettre en pause") {
                        try? JournalRepository(context: context).setRoutinePaused(!record.isPaused, for: dog.id)
                    }
                    .truffloTap(.selection)
                    .accessibilityIdentifier("routine.pause")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.truffloForest)
                .frame(minHeight: 44)
            } else {
                Text("Aucune. Le journal fonctionne sans routine.")
                    .font(.body)
                    .foregroundStyle(Color.truffloSlate)
                Button("Choisir une routine") { showRoutine = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.truffloForest)
                    .frame(minHeight: 44)
                    .truffloTap()
                    .accessibilityIdentifier("routine.create")
            }
        }
    }

    /// One card of the board: a small header with its symbol, then the content.
    private func card<Content: View>(title: String, systemImage: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.truffloForest)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .truffloBoardCard()
    }

    /// The dog's three latest balades, newest first.
    private var recentWalks: [WalkRecord] {
        guard let id = matches.first?.id else { return [] }
        let ids = Set(participations.filter { $0.dogID == id }.map(\.walkID))
        return finishedWalks.filter { ids.contains($0.id) }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
            .prefix(3).map { $0 }
    }

    private var lastWalkDate: Date? { recentWalks.first.map { $0.endedAt ?? $0.startedAt } }

    private var facts: JournalFacts { JournalFacts(walks: finishedWalks, links: participations) }

    /// Time is descriptive and safe to sum (`JournalFacts`); distance is not.
    private var recordedSeconds: TimeInterval {
        matches.first.map { facts.totalSeconds(for: $0.id) } ?? 0
    }

    private var walkCount: Int? {
        matches.first.map { facts.walkCount(for: $0.id) }
    }

    private func delete(dogID: UUID) {
        do {
            try JournalRepository(context: context).deleteDog(dogID)
            dismiss()
        } catch JournalError.profileMissing {
            storageError = "Ce chien n'est plus sur cet iPhone."
        } catch {
            storageError = "Rien n'a été supprimé. Les données précédentes ont été conservées."
        }
    }
}
