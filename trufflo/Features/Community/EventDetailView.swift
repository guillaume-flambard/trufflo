import SwiftUI

/// One event: where, when, who organizes, the rules, what changed, and the one
/// action that fits this person's situation. The organizer's tools, the
/// attendance question and the report menu are added to this screen by their
/// own steps; the participants list is read from the server, not kept.
struct EventDetailView: View {
    let eventID: UUID
    @Environment(CommunityModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var participants: [EventParticipantDTO] = []
    @State private var updates: [EventUpdateDTO] = []
    @State private var showJoin = false
    @State private var confirmWithdraw = false
    @State private var showReschedule = false
    @State private var showRepropose = false
    @State private var confirmCancel = false

    private var event: WalkEventDTO? { model.event(eventID) }

    var body: some View {
        Group {
            if let event {
                content(event)
            } else {
                TruffloNotice(title: "Cette sortie n'est plus disponible",
                              message: "Elle a été retirée, ou vous n'y avez plus accès.",
                              actionTitle: "Revenir aux sorties") { dismiss() }
            }
        }
        .background(Color.truffloSand.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.revision) { await loadExtras() }
    }

    private func loadExtras() async {
        participants = await model.participants(of: eventID)
        updates = await model.updates(of: eventID)
    }

    @ViewBuilder
    private func content(_ event: WalkEventDTO) -> some View {
        let isOrganizer = event.organizerID == model.userID
        ScrollView {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                    if event.status == .cancelled {
                        Label("Sortie annulée", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.truffloDanger)
                            .accessibilityIdentifier("event.cancelled")
                    }
                    Text(event.meetingPoint)
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.truffloForest)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(EventFormatting.day(event.startsAt)), \(EventFormatting.timeRange(event))")
                        .font(.title3)
                        .foregroundStyle(Color.truffloCharcoal)
                    Text("\(event.organizerName) organise, \(EventFormatting.duration(event.durationMinutes))")
                        .foregroundStyle(Color.truffloSlate)
                    Text(EventFormatting.places(event))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.truffloForest)
                        .padding(.top, TruffloTheme.Spacing.xxSmall)
                }

                CommunityErrorLine()

                if !updates.isEmpty { updatesSection }

                if !event.rules.isEmpty {
                    section("Règles de l'organisateur") {
                        Text(event.rules).foregroundStyle(Color.truffloCharcoal)
                    }
                }

                if !participants.isEmpty { participantsSection(event, isOrganizer: isOrganizer) }

                section("Où et quand") {
                    Text("Le point de rendez-vous est un lieu public choisi par l'organisateur. Aucune position n'est partagée par l'app.")
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                }
            }
            .padding(TruffloTheme.Spacing.large)
        }
        .safeAreaInset(edge: .bottom) { bottomAction(event, isOrganizer: isOrganizer) }
        .sheet(isPresented: $showJoin) { JoinSheet(event: event) }
        .sheet(isPresented: $showReschedule) { EventEditorView(mode: .reschedule(event)) }
        .sheet(isPresented: $showRepropose) { EventEditorView(mode: .create(prefill: event)) }
        .confirmationDialog("Annuler cette sortie ?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Annuler la sortie", role: .destructive) { Task { await model.cancelEvent(eventID) } }
        } message: {
            Text("Les personnes inscrites verront qu'elle est annulée.")
        }
        .confirmationDialog("Retirer votre demande ?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Me retirer", role: .destructive) { Task { await model.withdraw(eventID) } }
        } message: {
            Text("La place est libérée. Vous pourrez redemander tant qu'il en reste.")
        }
    }

    private var updatesSection: some View {
        section("Changements") {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                ForEach(updates) { update in
                    switch update.kind {
                    case .time: Text("Nouvel horaire : \(update.current)")
                    case .place: Text("Nouveau rendez-vous : \(update.current)")
                    case .cancelled: Text("La sortie est annulée.")
                    }
                }
            }
            .foregroundStyle(Color.truffloCharcoal)
            .accessibilityIdentifier("event.updates")
        }
    }

    private func participantsSection(_ event: WalkEventDTO, isOrganizer: Bool) -> some View {
        let shown = participants.filter { isOrganizer || $0.status == .accepted }
        let pending = shown.filter { $0.status == .requested }
        let accepted = shown.filter { $0.status == .accepted }
        return VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
            if isOrganizer && !pending.isEmpty {
                section("Demandes à traiter") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(pending) { person in
                            HStack(alignment: .center) {
                                personLine(person)
                                Spacer(minLength: TruffloTheme.Spacing.xSmall)
                                Button("Refuser") { Task { await model.decide(eventID, userID: person.userID, accept: false) } }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.truffloSlate)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityIdentifier("event.decline.\(person.displayName)")
                                Button("Accepter") { Task { await model.decide(eventID, userID: person.userID, accept: true) } }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.truffloForest)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityIdentifier("event.accept.\(person.displayName)")
                            }
                        }
                    }
                }
            }
            if !accepted.isEmpty {
                section(isOrganizer ? "Participants" : "Qui vient") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(accepted) { person in
                            HStack {
                                personLine(person)
                                Spacer()
                                if isOrganizer, let attended = person.attended {
                                    Text(attended ? "Était là" : "Absent")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Color.truffloSlate)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func personLine(_ person: EventParticipantDTO) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(person.displayName).font(.headline).foregroundStyle(Color.truffloCharcoal)
            Text(person.dogNames.isEmpty ? "Sans chien" : person.dogNames.formatted(.list(type: .and).locale(TruffloLocale.french)))
                .font(.footnote)
                .foregroundStyle(Color.truffloSlate)
        }
        .padding(.vertical, TruffloTheme.Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func bottomAction(_ event: WalkEventDTO, isOrganizer: Bool) -> some View {
        if isOrganizer {
            organizerBar(event)
        } else {
            VStack(spacing: TruffloTheme.Spacing.xSmall) {
                if EventFormatting.canRequest(event) {
                    Button { showJoin = true } label: {
                        Text("Demander à venir")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.roundedRectangle(radius: TruffloTheme.Radius.medium))
                    .tint(Color.truffloForest)
                    .accessibilityIdentifier("event.request")
                } else if event.myStatus == .requested || event.myStatus == .accepted, event.status == .published {
                    VStack(spacing: 2) {
                        Text(EventFormatting.myStatus(event) ?? "")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.truffloForest)
                        Button(event.myStatus == .accepted ? "Me retirer" : "Retirer ma demande") { confirmWithdraw = true }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("event.withdraw")
                    }
                    .frame(maxWidth: .infinity)
                } else if let status = EventFormatting.myStatus(event) {
                    Text(status).font(.headline).foregroundStyle(Color.truffloSlate)
                } else if event.humanPlacesLeft == 0 {
                    Text("Cette sortie est complète").font(.headline).foregroundStyle(Color.truffloSlate)
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.large)
            .padding(.vertical, TruffloTheme.Spacing.xSmall)
            .background(Color.truffloSand.opacity(0.95))
        }
    }

    @ViewBuilder
    private func organizerBar(_ event: WalkEventDTO) -> some View {
        VStack(spacing: TruffloTheme.Spacing.xxSmall) {
            if EventFormatting.hasEnded(event) || event.status != .published {
                Button { showRepropose = true } label: {
                    Text("Reproposer cette sortie")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: TruffloTheme.Radius.medium))
                .tint(Color.truffloForest)
                .accessibilityIdentifier("event.repropose")
            } else {
                Text("Vous organisez cette sortie")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.truffloForest)
                HStack(spacing: TruffloTheme.Spacing.large) {
                    Button("Changer l'heure ou le lieu") { showReschedule = true }
                        .accessibilityIdentifier("event.reschedule")
                    Button("Annuler la sortie", role: .destructive) { confirmCancel = true }
                        .accessibilityIdentifier("event.cancel")
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TruffloTheme.Spacing.large)
        .padding(.vertical, TruffloTheme.Spacing.xSmall)
        .background(Color.truffloSand.opacity(0.95))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            WalkSectionTitle(title)
            content()
        }
    }
}

/// Choose which dogs come, or come without one. A dog added here is the name
/// the others will see, and nothing else of the household's dog.
struct JoinSheet: View {
    let event: WalkEventDTO
    @Environment(CommunityModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: Set<UUID> = []
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    Text("Qui vient avec vous ?")
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.truffloForest)
                    Text("Seuls le nom des chiens choisis et votre prénom sont vus des personnes acceptées.")
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)

                    CommunityErrorLine()

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.myDogs) { dog in
                            Button { toggle(dog.id) } label: {
                                HStack {
                                    Text(dog.name).foregroundStyle(Color.truffloCharcoal)
                                    Spacer()
                                    Image(systemName: chosen.contains(dog.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.truffloForest)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(chosen.contains(dog.id) ? .isSelected : [])
                            .accessibilityIdentifier("join.dog.\(dog.name)")
                        }
                        if model.myDogs.isEmpty {
                            Text("Aucun chien annoncé pour l'instant. Vous pouvez en ajouter un, ou venir sans chien.")
                                .font(.subheadline)
                                .foregroundStyle(Color.truffloSlate)
                        }
                    }

                    HStack {
                        TextField("Ajouter un chien", text: $newName)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("join.newDog")
                            .modifier(FormFieldStyle())
                        Button("Ajouter") {
                            let name = newName
                            Task {
                                if let id = await model.addDog(name: name) { chosen.insert(id); newName = "" }
                            }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .frame(minHeight: 44)
                    }

                    Button {
                        Task {
                            await model.requestToJoin(event.id, dogIDs: Array(chosen))
                            if model.errorMessage == nil { dismiss() }
                        }
                    } label: {
                        Text(chosen.isEmpty ? "Demander à venir sans chien" : "Envoyer la demande")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.roundedRectangle(radius: TruffloTheme.Radius.medium))
                    .tint(Color.truffloForest)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("join.send")
                }
                .padding(TruffloTheme.Spacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.truffloSand.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func toggle(_ id: UUID) {
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
    }
}
