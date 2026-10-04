import Foundation
import SwiftUI
import SwiftData

@MainActor
struct DogFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var breedKind = "unknown"
    @State private var breedLabel = ""
    @State private var errorMessage: String?

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
                    if breedKind == "known" { TextField("Nom de la race", text: $breedLabel) }
                }
                Section {
                    Text("La race ne déclenche pas d'objectif automatique. L'âge et la photo seront ajoutés dans le prochain jalon.")
                        .font(.footnote)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Ajouter un chien")
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
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBreed = breedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 80 else {
            errorMessage = "Saisissez un nom de 1 à 80 caractères."
            return
        }
        guard breedKind != "known" || (!cleanBreed.isEmpty && cleanBreed.count <= 100) else {
            errorMessage = "Renseignez la race ou sélectionnez « Race inconnue »."
            return
        }
        let dog = DogRecord(name: cleanName, breedKind: breedKind,
                            breedLabel: breedKind == "known" ? cleanBreed : "")
        context.insert(dog)
        do { try context.save(); dismiss() }
        catch {
            context.rollback()
            errorMessage = "Le profil n'a pas été enregistré. Réessayez sans fermer ce formulaire."
        }
    }
}