import Foundation
import SwiftUI
import SwiftData

/// Creation and edit share one form: the rules are identical, only the title and
/// the target of the write differ. The profile is copied into state at init so
/// an edit never holds a reference that a concurrent delete could invalidate.
@MainActor
struct DogFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let dogID: UUID?

    @State private var name: String
    @State private var breedKind: String
    @State private var breedLabel: String
    @State private var errorMessage: String?

    init(profile: DogRecord? = nil) {
        self.dogID = profile?.id
        _name = State(initialValue: profile?.name ?? "")
        _breedKind = State(initialValue: profile?.breedKind ?? "unknown")
        _breedLabel = State(initialValue: profile?.breedLabel ?? "")
    }

    private var isEditing: Bool { dogID != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Votre chien") {
                    TextField("Nom", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("dog.name")
                    Picker("Race", selection: $breedKind) {
                        Text("Race inconnue").tag("unknown")
                        Text("Croisé").tag("mixed")
                        Text("Race connue").tag("known")
                    }
                    if breedKind == "known" {
                        TextField("Nom de la race", text: $breedLabel)
                            .accessibilityIdentifier("dog.breedLabel")
                    }
                }
                Section {
                    Text("La race ne déclenche pas d'objectif automatique. L'âge et la photo seront ajoutés dans le prochain jalon.")
                        .font(.footnote)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("dog.error")
                    }
                }
            }
            .navigationTitle(isEditing ? "Modifier le chien" : "Ajouter un chien")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .accessibilityIdentifier("dog.save")
                }
            }
        }
    }

    private func save() {
        do {
            let input = try DogInput(name: name, breedKind: breedKind, breedLabel: breedLabel)
            let repository = JournalRepository(context: context)
            if let dogID { try repository.updateDog(dogID, with: input) }
            else { try repository.addDog(input) }
            dismiss()
        } catch DogError.invalidName {
            announce("Saisissez un nom de 1 à 80 caractères.")
        } catch DogError.invalidBreedLabel {
            announce("Renseignez la race ou sélectionnez « Race inconnue ».")
        } catch JournalError.profileMissing {
            announce("Ce profil n'existe plus. Fermez ce formulaire.")
        } catch {
            announce("Le profil n'a pas été enregistré. Réessayez sans fermer ce formulaire.")
        }
    }

    private func announce(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
    }
}
