import SwiftUI

/// What an organizer writes: when, how long, where, the rules, the places.
/// Creating and « reproposing » share this form; changing a coming event only
/// moves its time and place, so the registered are told what changed.
struct EventEditorView: View {
    enum Mode: Equatable {
        case create(prefill: WalkEventDTO?)
        case reschedule(WalkEventDTO)
    }

    let mode: Mode
    @Environment(CommunityModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var startsAt = Date()
    @State private var minutes = 60
    @State private var point = ""
    @State private var rules = ""
    @State private var humans = 6
    @State private var dogs = 6
    @State private var problem: String?

    private var isReschedule: Bool { if case .reschedule = mode { true } else { false } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    Text(isReschedule ? "Changer l'heure ou le lieu" : "Proposer une sortie")
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.truffloForest)
                    if isReschedule {
                        Text("Les personnes inscrites sont prévenues et peuvent se retirer.")
                            .font(.subheadline)
                            .foregroundStyle(Color.truffloSlate)
                    }

                    if let problem {
                        Label(problem, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.truffloDanger)
                            .accessibilityIdentifier("editor.problem")
                    }
                    CommunityErrorLine()

                    field("Date et heure") {
                        DatePicker("Date et heure", selection: $startsAt, in: Date()...)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .environment(\.locale, TruffloLocale.french)
                            .accessibilityIdentifier("editor.date")
                    }

                    field("Point de rendez-vous, un lieu public") {
                        TextField("Entrée nord du parc", text: $point)
                            .accessibilityIdentifier("editor.point")
                            .modifier(FormFieldStyle())
                    }

                    if !isReschedule {
                        field("Durée") {
                            Stepper(EventFormatting.duration(minutes), value: $minutes, in: 15...240, step: 15)
                                .accessibilityIdentifier("editor.duration")
                        }
                        field("Règles, si vous en avez") {
                            TextField("En laisse, chiens sociables", text: $rules, axis: .vertical)
                                .lineLimit(2...5)
                                .accessibilityIdentifier("editor.rules")
                                .modifier(FormFieldStyle())
                        }
                        field("Personnes, vous compris") {
                            Stepper("\(humans)", value: $humans, in: 1...30)
                                .accessibilityIdentifier("editor.humans")
                        }
                        field("Chiens") {
                            Stepper("\(dogs)", value: $dogs, in: 1...30)
                                .accessibilityIdentifier("editor.dogs")
                        }
                    }

                    Button(action: save) {
                        Text(isReschedule ? "Prévenir les inscrits" : "Publier la sortie")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color.truffloForest)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("editor.save")
                }
                .padding(TruffloTheme.Spacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.truffloSand.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
        .presentationDetents([.large])
        .onAppear(perform: fill)
    }

    private func fill() {
        switch mode {
        case .create(let prefill):
            if let old = prefill {
                // Reproposed: same place, rules and places, one week later.
                startsAt = max(old.startsAt.addingTimeInterval(7 * 86400), Date().addingTimeInterval(3600))
                minutes = old.durationMinutes; point = old.meetingPoint; rules = old.rules
                humans = old.humanCapacity; dogs = old.dogCapacity
            } else {
                startsAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86400)
            }
        case .reschedule(let event):
            startsAt = event.startsAt; point = event.meetingPoint
        }
    }

    private func save() {
        problem = nil
        Task {
            switch mode {
            case .create:
                do {
                    let draft = try WalkEventDraft(startsAt: startsAt, durationMinutes: minutes, meetingPoint: point,
                                                   rules: rules, humanCapacity: humans, dogCapacity: dogs)
                    if await model.createEvent(draft) != nil { dismiss() }
                } catch CommunityError.invalid(let text) {
                    problem = text
                } catch {
                    problem = CommunityModel.message(for: error)
                }
            case .reschedule(let event):
                let clean = point.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty, clean.count <= 120 else { problem = "Indiquez un point de rendez-vous public."; return }
                guard startsAt > Date() else { problem = "La sortie doit être à venir."; return }
                await model.updateEvent(event.id, startsAt: startsAt, meetingPoint: clean)
                if model.errorMessage == nil { dismiss() }
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Color.truffloSlate)
            content()
        }
    }
}
