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
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    label("Qui était là ?") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                                ForEach(dogs) { dog in dogChip(dog) }
                            }
                        }
                    }

                    label("Durée") {
                        HStack(alignment: .firstTextBaseline, spacing: TruffloTheme.Spacing.xSmall) {
                            TextField("0", text: $minutesText)
                                .keyboardType(.decimalPad)
                                .font(.truffloFigure(.largeTitle))
                                .foregroundStyle(Color.truffloForest)
                                .fixedSize()
                                .accessibilityLabel("Durée en minutes")
                                .accessibilityIdentifier("walk.minutes")
                            Text("min")
                                .font(.title3)
                                .foregroundStyle(Color.truffloSlate)
                            Spacer(minLength: 0)
                        }
                        .modifier(FormFieldStyle())
                    }

                    label("Fin de la balade") {
                        DatePicker("Fin de la balade", selection: $endedAt, in: ...Date(),
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Color.truffloForest)
                            .environment(\.locale, Locale(identifier: "fr_FR"))
                    }

                    label("Note") {
                        TextField("Comment s'est passée la balade ?", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .accessibilityIdentifier("walk.note")
                            .modifier(FormFieldStyle())
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.truffloDanger)
                    }

                    Text("Durée déclarée. Aucune distance n'est calculée.")
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                }
                .padding(.horizontal, TruffloTheme.Spacing.large)
                .padding(.vertical, TruffloTheme.Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Ajouter au journal")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.truffloForest)
                .accessibilityIdentifier("walk.save")
                .padding(.horizontal, TruffloTheme.Spacing.large)
                .padding(.bottom, TruffloTheme.Spacing.xSmall)
            }
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationTitle("Balade passée")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .onAppear {
            if selectedDogs.isEmpty, let first = dogs.first { selectedDogs.insert(first.id) }
        }
    }

    /// Dogs are picked by their face, the way they appear everywhere else.
    private func dogChip(_ dog: DogRecord) -> some View {
        let isOn = selectedDogs.contains(dog.id)
        return Button {
            if isOn { selectedDogs.remove(dog.id) } else { selectedDogs.insert(dog.id) }
        } label: {
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                TruffloDogPortrait(name: dog.name, photoData: dog.photoData, diameter: 32)
                Text(dog.name).font(.subheadline.weight(.semibold))
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .frame(minHeight: 44)
            .foregroundStyle(isOn ? Color.white : Color.truffloCharcoal)
            .background(isOn ? Color.truffloForest : Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.truffloForest.opacity(isOn ? 0 : 0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func label<Content: View>(_ text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.truffloSlate)
            content()
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
