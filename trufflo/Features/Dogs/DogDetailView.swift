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
        List {
            Section("Profil") {
                LabeledContent("Nom") {
                    Text(dog.name)
                        .font(.truffloHeadline)
                        .foregroundStyle(Color.truffloForest)
                }
                LabeledContent("Race") {
                    TruffloBadge(dog.breedDescription, icon: "pawprint.fill", style: .sage)
                }
            }

            Section {
                Button {
                    showEdit = true
                } label: {
                    Label("Modifier", systemImage: "pencil")
                        .font(.truffloSubheadline)
                        .foregroundStyle(Color.truffloForest)
                }
                .accessibilityIdentifier("dog.edit")

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Supprimer le profil", systemImage: "trash")
                        .font(.truffloSubheadline)
                        .foregroundStyle(Color.truffloDanger)
                }
                .accessibilityIdentifier("dog.delete")
                .accessibilityLabel("Supprimer le profil de \(dog.name)")
            } footer: {
                Text("La suppression retire le profil de cet appareil. Vos balades déjà enregistrées gardent le nom de votre chien.")
                    .font(.truffloCaption)
                    .foregroundStyle(Color.truffloSlate)
            }
        }
        .sheet(isPresented: $showEdit) { DogFormView(profile: dog) }
        .confirmationDialog("Supprimer ce profil ?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Supprimer \(dog.name)", role: .destructive) { delete(dogID: dog.id) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ce profil sera supprimé. Les balades déjà enregistrées conservent le nom de votre chien.")
        }
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
