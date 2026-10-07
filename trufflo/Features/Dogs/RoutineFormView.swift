import SwiftUI
import SwiftData

/// Choosing a routine (PRD F04). Every reference point is optional and starts
/// unset: the app suggests no number, and nothing depends on the breed.
@MainActor
struct RoutineFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let dogID: UUID
    private let dogName: String
    private let isNew: Bool

    @State private var choosesWalks: Bool
    @State private var walks: Int
    @State private var choosesMinutes: Bool
    @State private var minutes: Int
    @State private var slots: Set<DogRoutine.Slot>
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    init(dogID: UUID, dogName: String, current: DogRoutine?) {
        self.dogID = dogID
        self.dogName = dogName
        isNew = current == nil
        _choosesWalks = State(initialValue: current?.walksPerDay != nil)
        _walks = State(initialValue: current?.walksPerDay ?? 2)
        _choosesMinutes = State(initialValue: current?.minutesPerWalk != nil)
        _minutes = State(initialValue: current?.minutesPerWalk ?? 30)
        _slots = State(initialValue: current?.slots ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    Text("Vos propres repères pour \(dogName). Le journal fonctionne sans, et rien ne vous sera reproché si une journée s'en écarte.")
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)

                    reference(title: "Nombre de balades par jour", isOn: $choosesWalks) {
                        Stepper(value: $walks, in: 1...8) {
                            Text(walks == 1 ? "1 balade" : "\(walks) balades")
                                .font(.truffloFigure(.title2))
                                .foregroundStyle(Color.truffloForest)
                        }
                        .accessibilityIdentifier("routine.walks")
                    }

                    reference(title: "Durée d'une balade", isOn: $choosesMinutes) {
                        Stepper(value: $minutes, in: 5...240, step: 5) {
                            Text("environ \(minutes) min")
                                .font(.truffloFigure(.title2))
                                .foregroundStyle(Color.truffloForest)
                        }
                        .accessibilityIdentifier("routine.minutes")
                    }

                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                        Text("Moments de la journée")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.truffloSlate)
                        HStack(spacing: TruffloTheme.Spacing.xSmall) {
                            ForEach(DogRoutine.Slot.allCases, id: \.self) { slot in slotChip(slot) }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.truffloDanger)
                    }

                    if !isNew {
                        Button("Supprimer la routine") { confirmDelete = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.truffloDanger)
                            .frame(minHeight: 44)
                            .truffloTap(.impact(weight: .medium))
                            .accessibilityIdentifier("routine.delete")
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.vertical, TruffloTheme.Spacing.medium)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Enregistrer la routine")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.truffloForest)
                .truffloTap()
                .accessibilityIdentifier("routine.save")
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.bottom, TruffloTheme.Spacing.xSmall)
            }
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationTitle("Routine choisie")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
            .confirmationDialog("Supprimer la routine ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    try? JournalRepository(context: context).deleteRoutine(for: dogID)
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les balades enregistrées ne changent pas.")
            }
        }
    }

    private func reference<Content: View>(title: String, isOn: Binding<Bool>,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            Toggle(isOn: isOn) {
                Text(title).font(.headline).foregroundStyle(Color.truffloCharcoal)
            }
            .tint(Color.truffloForest)
            if isOn.wrappedValue { content() }
        }
        .padding(TruffloTheme.Spacing.medium)
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
            .strokeBorder(Color.truffloForest.opacity(0.08), lineWidth: 1))
    }

    private func slotChip(_ slot: DogRoutine.Slot) -> some View {
        let isOn = slots.contains(slot)
        return Button {
            if isOn { slots.remove(slot) } else { slots.insert(slot) }
        } label: {
            Text(slot.label.prefix(1).uppercased() + slot.label.dropFirst())
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isOn ? Color.white : Color.truffloCharcoal)
                .background(isOn ? Color.truffloForest : Color.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.truffloForest.opacity(isOn ? 0 : 0.15), lineWidth: 1))
        }
        .buttonStyle(TruffloPressStyle())
        .truffloTap(.selection)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func save() {
        do {
            let routine = try DogRoutine(walksPerDay: choosesWalks ? walks : nil,
                                         minutesPerWalk: choosesMinutes ? minutes : nil,
                                         slots: slots)
            try JournalRepository(context: context).saveRoutine(routine, for: dogID)
            dismiss()
        } catch DogRoutine.Invalid.empty {
            errorMessage = "Choisissez au moins un repère, ou annulez : le journal fonctionne sans routine."
        } catch {
            errorMessage = "La routine n'a pas été enregistrée."
        }
    }
}
