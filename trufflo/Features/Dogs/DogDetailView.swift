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

    @State private var showEdit = false
    @State private var showDeleteConfirmation = false
    @State private var storageError: String?

    init(dogID: UUID) {
        _matches = Query(filter: #Predicate<DogRecord> { $0.id == dogID })
    }

    var body: some View {
        Group {
            if let dog = matches.first {
                content(for: dog)
            } else {
                TruffloEmptyStateView(
                    imageName: "EmptyDog",
                    title: "Ce profil n'existe plus",
                    description: "Il a été supprimé de cet appareil."
                )
            }
        }
        .navigationTitle(matches.first?.name ?? "Chien")
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
                TruffloDogHero(name: dog.name, photoData: dog.photoData)

                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    identity(of: dog)

                    if let count = walkCount, count > 0 {
                        TruffloStatRow {
                            TruffloStat("Balades", value: "\(count)")
                            TruffloStat("Temps enregistré", value: WalkFormatting.minutes(recordedSeconds))
                        }
                    }

                    if !dog.preferencesNote.isEmpty {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                            WalkSectionTitle("Préférences de sortie")
                            Text(dog.preferencesNote)
                                .font(.body)
                                .foregroundStyle(Color.truffloCharcoal)
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
        .sheet(isPresented: $showEdit) { DogFormView(profile: dog) }
        .confirmationDialog("Supprimer ce profil ?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Supprimer \(dog.name)", role: .destructive) { delete(dogID: dog.id) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ce profil sera supprimé. Les balades déjà enregistrées conservent le nom de votre chien.")
        }
    }

    /// Breed, then age and sex joined with a comma. What the person declared and
    /// nothing else: no trait is read from the walks.
    private func identity(of dog: DogRecord) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                // An unknown breed is the absence of a fact, not a fact to print.
                if dog.breedKind != "unknown" {
                    Text(dog.breedDescription)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.truffloCharcoal)
                }
                let details = [dog.ageDescription, dog.genderDescription]
                    .filter { !$0.isEmpty && $0 != "Non renseigné" }
                if !details.isEmpty {
                    Text(details.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                }
            }
            Button {
                showEdit = true
            } label: {
                Label("Modifier", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, TruffloTheme.Spacing.xSmall)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glass)
            .tint(Color.truffloForest)
            .accessibilityIdentifier("dog.edit")
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
