import SwiftUI

/// What the form keeps once a breed is picked: the same two fields as before
/// (`breedKind`, `breedLabel`), so nothing is added to the store or the server.
struct BreedChoice: Equatable {
    var kind: String
    var label: String

    static let mixed = BreedChoice(kind: "mixed", label: "")
    static let unknown = BreedChoice(kind: "unknown", label: "")

    /// What the form's row shows.
    var summary: String {
        switch kind {
        case "known": label
        case "mixed": "Croisé"
        default: "Je ne sais pas"
        }
    }
}

/// Search the breed catalogue (A-REQ-03). Three answers are always visible
/// without typing, because a crossbreed or an unknown breed is an answer, not
/// a failure to find one. "Autre race" keeps the free text field the form had.
struct BreedPickerView: View {
    let current: BreedChoice
    let onPick: (BreedChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var typingOther = false
    @State private var otherLabel = ""
    @FocusState private var otherFocused: Bool

    private var results: [Breed] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? BreedCatalog.all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            : BreedCatalog.search(query)
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        quickRow("Croisé", choice: .mixed, id: "breed.mixed")
                        quickRow("Je ne sais pas", choice: .unknown, id: "breed.unknown")
                        Button {
                            withAnimation { typingOther = true }
                            otherFocused = true
                        } label: {
                            row("Autre race", selected: current.kind == "known" && BreedCatalog.entry(named: current.label) == nil)
                        }
                        .accessibilityIdentifier("breed.other")
                        if typingOther {
                            HStack {
                                TextField("Nom de la race", text: $otherLabel)
                                    .focused($otherFocused)
                                    .submitLabel(.done)
                                    .onSubmit(useOther)
                                    .accessibilityIdentifier("dog.breedLabel")
                                Button("Utiliser", action: useOther)
                                    .disabled(otherLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }

                Section(query.isEmpty ? "Toutes les races" : "Résultats") {
                    ForEach(results) { breed in
                        Button {
                            pick(BreedChoice(kind: "known", label: breed.name))
                        } label: {
                            row(breed.name, selected: current.kind == "known" && current.label == breed.name)
                        }
                        .accessibilityIdentifier("breed.\(breed.id)")
                    }
                    if results.isEmpty {
                        // Nothing matches: what was typed can still be the answer.
                        Button {
                            pick(BreedChoice(kind: "known", label: query.trimmingCharacters(in: .whitespaces)))
                        } label: {
                            row("Utiliser « \(query.trimmingCharacters(in: .whitespaces)) »", selected: false)
                        }
                        .accessibilityIdentifier("breed.useTyped")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.truffloSand.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Chercher une race")
            .navigationTitle("Race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .onAppear {
            if current.kind == "known", BreedCatalog.entry(named: current.label) == nil {
                otherLabel = current.label
            }
        }
    }

    private func quickRow(_ title: String, choice: BreedChoice, id: String) -> some View {
        Button { pick(choice) } label: { row(title, selected: current == choice) }
            .accessibilityIdentifier(id)
    }

    private func row(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.truffloCharcoal)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.truffloForest)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func useOther() {
        let label = otherLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        pick(BreedChoice(kind: "known", label: label))
    }

    private func pick(_ choice: BreedChoice) {
        onPick(choice)
        dismiss()
    }
}
