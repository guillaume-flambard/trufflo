import Foundation
import SwiftUI
import SwiftData

@MainActor
struct ManualWalkFormView: View {
    let dogs: [DogRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDogs: Set<UUID> = []
    @State private var minutesText = ""
    @State private var endedAt = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Chiens présents") {
                    ForEach(dogs) { dog in
                        Toggle(dog.name, isOn: Binding(
                            get: { selectedDogs.contains(dog.id) },
                            set: { selected in
                                if selected { selectedDogs.insert(dog.id) }
                                else { selectedDogs.remove(dog.id) }
                            }
                        ))
                    }
                }
                Section("Balade passée") {
                    DatePicker("Fin de la balade", selection: $endedAt,
                               in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    TextField("Durée en minutes", text: $minutesText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("walk.minutes")
                    TextField("Note facultative", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                    Text("Durée déclarée. Aucune distance ni aucun pas ne sont inventés.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Ajouter une balade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .accessibilityIdentifier("walk.save")
                }
            }
        }
        .onAppear {
            if selectedDogs.isEmpty, let first = dogs.first { selectedDogs.insert(first.id) }
        }
    }

    private func save() {
        let normalized = minutesText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let minutes = Double(normalized), endedAt <= Date() else {
            errorMessage = "Saisissez une durée valide et une date de fin passée."
            return
        }
        do {
            let input = try ManualWalkInput(dogIDs: Array(selectedDogs),
                                            durationSeconds: minutes * 60, note: note)
            try JournalRepository(context: context).addManualWalk(input, endedAt: endedAt)
            dismiss()
        } catch WalkError.missingDog {
            errorMessage = "Sélectionnez au moins un chien."
        } catch WalkError.noteTooLong {
            errorMessage = "La note doit contenir au maximum 500 caractères."
        } catch JournalError.profileMissing {
            errorMessage = "Un profil a changé. Rouvrez ce formulaire."
        } catch JournalError.persistence {
            errorMessage = "La balade n'a pas été enregistrée. Les valeurs saisies restent disponibles."
        } catch {
            errorMessage = "La durée doit être positive, finie et ne pas dépasser 24 heures."
        }
    }
}