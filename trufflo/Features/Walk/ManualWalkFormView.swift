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
    @State private var title = ""
    @State private var mood: WalkMood?
    @State private var errorMessage: String?
    @State private var didSave = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TruffloScreenHeader(title: "Balade passée",
                                        subtitle: "Une balade faite sans l'app, ajoutée au journal.")
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
                            .environment(\.locale, TruffloLocale.french)
                    }

                    label("Titre (facultatif)") {
                        TextField("Ex. Tour du parc", text: $title)
                            .accessibilityIdentifier("walk.title.field")
                            .modifier(FormFieldStyle())
                    }

                    label("Humeur (facultatif)") {
                        MoodChips(selection: $mood)
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

                    Text("Une balade ajoutée garde sa durée, sans distance.")
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.vertical, TruffloTheme.Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    HStack(spacing: TruffloTheme.Spacing.xSmall) {
                        if didSave {
                            Image(systemName: "checkmark")
                                .font(.headline)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(didSave ? "Ajoutée" : "Ajouter au journal")
                            .font(.headline)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.truffloForest)
                .disabled(didSave)
                .truffloTap()
                .accessibilityIdentifier("walk.save")
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.bottom, TruffloTheme.Spacing.xSmall)
                .truffloBottomBarFade()
            }
            .truffloAura()
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationTitle("Balade passée")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                // The title is the head of the page, not repeated small in the bar.
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
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
                // A face only when there is a photo: no initial on a disc.
                if let face = dog.photoData {
                    TruffloDogPortrait(name: dog.name, photoData: face, diameter: 32)
                }
                Text(dog.name).font(.subheadline.weight(.semibold))
            }
            .padding(.leading, dog.photoData == nil ? 16 : 6)
            .padding(.trailing, 16)
            .frame(minHeight: 44)
            .foregroundStyle(isOn ? Color.white : Color.truffloCharcoal)
            .background(isOn ? Color.truffloForest : Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.truffloForest.opacity(isOn ? 0 : 0.15), lineWidth: 1))
        }
        .buttonStyle(TruffloPressStyle())
        .truffloTap(.selection)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// One field as a white card with its title inside, as on the dog form.
    private func label<Content: View>(_ text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.truffloSlate)
            content()
        }
        .truffloBoardCard(padding: 14)
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
            let repository = JournalRepository(context: context)
            let walk = try repository.addManualWalk(input, endedAt: endedAt)
            if !title.trimmingCharacters(in: .whitespaces).isEmpty || mood != nil {
                try repository.updateWalkDetails(walk.id, title: title, mood: mood, note: walk.note)
            }
            confirmAndDismiss()
        } catch WalkError.missingDog {
            errorMessage = "Sélectionnez au moins un chien."
        } catch WalkError.noteTooLong {
            errorMessage = "La note doit contenir au maximum 500 caractères."
        } catch WalkError.titleTooLong {
            errorMessage = "Le titre doit contenir au maximum 80 caractères."
        } catch JournalError.profileMissing {
            errorMessage = "Un chien a changé. Rouvrez ce formulaire."
        } catch JournalError.persistence {
            errorMessage = "La balade n'a pas été enregistrée. Les valeurs saisies restent disponibles."
        } catch {
            errorMessage = "La durée doit être positive, finie et ne pas dépasser 24 heures."
        }
    }

    /// The write already happened: this is not a wait for it to finish, only a
    /// beat long enough for "Ajoutée" to register before the sheet closes,
    /// instead of vanishing the instant the write completes.
    private func confirmAndDismiss() {
        guard !reduceMotion else { dismiss(); return }
        withAnimation(TruffloTheme.Motion.selection(reduceMotion: reduceMotion)) { didSave = true }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            dismiss()
        }
    }
}
