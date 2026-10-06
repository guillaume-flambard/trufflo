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
    @Query private var routines: [RoutineRecord]
    @Query(filter: #Predicate<WalkRecord> { $0.phaseRaw == "completed" }) private var finishedWalks: [WalkRecord]

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
                TruffloNotice(title: "Ce profil n'existe plus", message: "Il a été retiré de cet iPhone depuis un autre écran.", actionTitle: "Revenir à la liste") { dismiss() }
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
                            Label("Ajouter une photo", systemImage: "camera")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, TruffloTheme.Spacing.medium)
                                .frame(minHeight: 44)
                                .background(Color.white.opacity(0.7), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.truffloForest)
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
                            WalkSectionTitle("Préférences de sortie")
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
                            Text("Supprimer le profil")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.truffloDanger)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("dog.delete")
                        .accessibilityLabel("Supprimer le profil de \(dog.name)")
                        Text("La suppression retire le profil de cet appareil. Vos balades déjà enregistrées gardent le nom de votre chien.")
                            .font(.footnote)
                            .foregroundStyle(Color.truffloSlate)
                    }
                    .padding(.top, TruffloTheme.Spacing.small)
                }
                .padding(.horizontal, TruffloTheme.Spacing.large)
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
        .confirmationDialog("Supprimer ce profil ?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Supprimer \(dog.name)", role: .destructive) { delete(dogID: dog.id) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ce profil sera supprimé. Les balades déjà enregistrées conservent le nom de votre chien.")
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
                        .accessibilityIdentifier("routine.edit")
                    Button(record.isPaused ? "Reprendre" : "Mettre en pause") {
                        try? JournalRepository(context: context).setRoutinePaused(!record.isPaused, for: dog.id)
                    }
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
                    .accessibilityIdentifier("routine.create")
            }
        }
    }

    /// Time is descriptive and safe to sum: every walk has a duration, declared
    /// or measured. Distance is not, so it is not summed here.
    private var recordedSeconds: TimeInterval {
        guard let dog = matches.first else { return 0 }
        let mine = Set(participations.filter { $0.dogID == dog.id }.map(\.walkID))
        return finishedWalks.filter { mine.contains($0.id) }.map(\.confirmedSeconds).reduce(0, +)
    }

    private var walkCount: Int? {
        guard let dog = matches.first else { return nil }
        // A walk counts for a dog through its participation record, and only
        // once it is finished; a recording in progress is not yet a walk.
        let finished = Set(finishedWalks.map(\.id))
        return participations.filter { $0.dogID == dog.id && finished.contains($0.walkID) }.count
    }

    private func delete(dogID: UUID) {
        do {
            try JournalRepository(context: context).deleteDog(dogID)
            dismiss()
        } catch JournalError.profileMissing {
            storageError = "Ce profil n'existe plus."
        } catch {
            storageError = "Le profil n'a pas été supprimé. Les données précédentes ont été conservées."
        }
    }
}
