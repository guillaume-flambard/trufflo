import SwiftUI
import SwiftData

/// Corrects a finished walk (PRD F05). A declared walk can change its dogs,
/// duration, end and note; a recorded walk only its dogs and note, because its
/// duration and route were measured. The walk is then shown as corrected.
@MainActor
struct WalkCorrectionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]

    private let walkID: UUID
    private let isManual: Bool
    /// Participants whose profile no longer exists: kept on the walk, shown by
    /// their recorded name, not removable from here.
    private let orphanedParticipants: [(id: UUID, name: String)]

    @State private var selectedDogs: Set<UUID>
    @State private var minutesText: String
    @State private var endedAt: Date
    @State private var note: String
    @State private var errorMessage: String?

    init(walk: WalkRecord, participants: [WalkDogRecord], existingDogIDs: Set<UUID>) {
        walkID = walk.id
        isManual = walk.source == .manual
        orphanedParticipants = participants
            .filter { !existingDogIDs.contains($0.dogID) }
            .map { ($0.dogID, $0.dogNameSnapshot) }
        _selectedDogs = State(initialValue: Set(participants.map(\.dogID)))
        _minutesText = State(initialValue: (walk.confirmedSeconds / 60)
            .formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR"))))
        _endedAt = State(initialValue: walk.endedAt ?? walk.startedAt)
        _note = State(initialValue: walk.note)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    section("Qui était là ?") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                                ForEach(dogs) { dog in chip(id: dog.id, name: dog.name, photo: dog.photoData, removable: true) }
                                ForEach(orphanedParticipants, id: \.id) { chip(id: $0.id, name: $0.name, photo: nil, removable: false) }
                            }
                        }
                    }

                    if isManual {
                        section("Durée") {
                            HStack(alignment: .firstTextBaseline, spacing: TruffloTheme.Spacing.xSmall) {
                                TextField("0", text: $minutesText)
                                    .keyboardType(.decimalPad)
                                    .font(.truffloFigure(.largeTitle))
                                    .foregroundStyle(Color.truffloForest)
                                    .fixedSize()
                                    .accessibilityLabel("Durée en minutes")
                                    .accessibilityIdentifier("walk.correct.minutes")
                                Text("min").font(.title3).foregroundStyle(Color.truffloSlate)
                                Spacer(minLength: 0)
                            }
                            .modifier(FormFieldStyle())
                        }
                        section("Fin de la balade") {
                            DatePicker("Fin de la balade", selection: $endedAt, in: ...Date(),
                                       displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .tint(Color.truffloForest)
                                .environment(\.locale, Locale(identifier: "fr_FR"))
                        }
                    } else {
                        Text("La durée et le parcours ont été mesurés par GPS : ils ne se corrigent pas. Les chiens présents et la note, si.")
                            .font(.subheadline)
                            .foregroundStyle(Color.truffloSlate)
                    }

                    section("Note") {
                        TextField("Comment s'est passée la balade ?", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .accessibilityIdentifier("walk.correct.note")
                            .modifier(FormFieldStyle())
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.truffloDanger)
                    }

                    Text("La balade sera marquée comme corrigée.")
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                }
                .padding(.horizontal, TruffloTheme.Spacing.large)
                .padding(.vertical, TruffloTheme.Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Enregistrer la correction")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.truffloForest)
                .accessibilityIdentifier("walk.correct.save")
                .padding(.horizontal, TruffloTheme.Spacing.large)
                .padding(.bottom, TruffloTheme.Spacing.xSmall)
            }
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationTitle("Corriger la balade")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func chip(id: UUID, name: String, photo: Data?, removable: Bool) -> some View {
        let isOn = selectedDogs.contains(id)
        return Button {
            guard removable else { return }
            if isOn { selectedDogs.remove(id) } else { selectedDogs.insert(id) }
        } label: {
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                // A face only when there is a photo: no initial on a disc.
                if let face = photo {
                    TruffloDogPortrait(name: name, photoData: face, diameter: 32)
                }
                Text(name).font(.subheadline.weight(.semibold))
            }
            .padding(.leading, photo == nil ? 16 : 6)
            .padding(.trailing, 16)
            .frame(minHeight: 44)
            .foregroundStyle(isOn ? Color.white : Color.truffloCharcoal)
            .background(isOn ? Color.truffloForest : Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.truffloForest.opacity(isOn ? 0 : 0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Color.truffloSlate)
            content()
        }
    }

    private func save() {
        var duration: TimeInterval?
        if isManual {
            let normalized = minutesText.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")
            guard let minutes = Double(normalized) else {
                errorMessage = "Saisissez une durée en minutes."
                return
            }
            duration = minutes * 60
        }
        do {
            let correction = try WalkCorrection(dogIDs: Array(selectedDogs), note: note,
                                                durationSeconds: duration,
                                                endedAt: isManual ? endedAt : nil)
            try JournalRepository(context: context).correctWalk(walkID, with: correction)
            dismiss()
        } catch WalkError.missingDog {
            errorMessage = "Gardez au moins un chien sur la balade."
        } catch WalkError.invalidDuration {
            errorMessage = "La durée doit être positive, au plus 24 heures, et la balade ne peut pas finir dans le futur."
        } catch WalkError.noteTooLong {
            errorMessage = "La note doit contenir au maximum 500 caractères."
        } catch JournalError.profileMissing {
            errorMessage = "Un profil a changé. Rouvrez la correction."
        } catch {
            errorMessage = "La correction n'a pas été enregistrée. La balade est inchangée."
        }
    }
}
