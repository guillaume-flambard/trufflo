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

                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    if let count = walkCount, count > 0 {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                            Text(String(localized: "\(count) balades enregistrées"))
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.truffloForest)
                            Text("\(WalkFormatting.minutes(recordedSeconds)) en tout.")
                                .font(.subheadline)
                                .foregroundStyle(Color.truffloSlate)
                        }
                    }

                    routineSection(for: dog)

                    HouseholdPrompt(place: .profile, dogName: dog.name) { showHousehold = true }

                    if !dog.preferencesNote.isEmpty {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                            WalkSectionTitle("Préférences de balade")
                            Text(dog.preferencesNote)
                                .font(.body)
                                .foregroundStyle(Color.truffloCharcoal)
                            Text("Écrit par vous")
                                .font(.footnote)
                                .foregroundStyle(Color.truffloSlate)
                        }
                    }

                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Text("Supprimer \(dog.name)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.truffloDanger)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .truffloTap(.impact(weight: .medium))
                        .accessibilityIdentifier("dog.delete")
                        .accessibilityLabel("Supprimer \(dog.name)")
                        Text("\(dog.name) est retiré de cet iPhone. Les balades déjà enregistrées gardent son nom.")
                            .font(.footnote)
                            .foregroundStyle(Color.truffloSlate)
                    }
                    .padding(.top, TruffloTheme.Spacing.small)
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
            WalkSectionTitle("Routine choisie")
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
