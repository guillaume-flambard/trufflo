import SwiftUI

/// One outing: where, when, who organizes, the rules, what changed, and the one
/// action that fits this person's situation. The organizer's tools, the
/// attendance question and the report menu are added to this screen by their
/// own steps; the participants list is read from the server, not kept.
struct OutingDetailView: View {
    let outingID: UUID
    @Environment(CommunityModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var participants: [OutingParticipantDTO] = []
    @State private var updates: [OutingUpdateDTO] = []
    @State private var showJoin = false
    @State private var confirmWithdraw = false
    @State private var showReschedule = false
    @State private var showRepropose = false
    @State private var confirmCancel = false
    @State private var showReportOuting = false
    @State private var showReportPerson = false
    @State private var confirmBlock = false

    private var outing: OutingDTO? { model.outing(outingID) }

    var body: some View {
        Group {
            if let outing {
                content(outing)
            } else {
                TruffloNotice(title: "Cette sortie n'est plus disponible",
                              message: "Elle a été retirée, ou vous n'y avez plus accès.",
                              actionTitle: "Revenir aux sorties") { dismiss() }
            }
        }
        .background(Color.truffloSand.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let outing, outing.organizerID != model.userID {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Plus", systemImage: "ellipsis.circle") {
                        Button("Signaler cette sortie", systemImage: "flag") { showReportOuting = true }
                        Button("Signaler \(outing.organizerName)", systemImage: "person.crop.circle.badge.exclamationmark") {
                            showReportPerson = true
                        }
                        Divider()
                        Button("Bloquer \(outing.organizerName)", systemImage: "hand.raised", role: .destructive) {
                            confirmBlock = true
                        }
                    }
                    .accessibilityIdentifier("outing.menu")
                }
            }
        }
        .sheet(isPresented: $showReportOuting) {
            if let outing { ReportSheet(target: .outing, targetID: outing.id, title: outing.meetingPoint) }
        }
        .sheet(isPresented: $showReportPerson) {
            if let outing { ReportSheet(target: .profile, targetID: outing.organizerID, title: outing.organizerName) }
        }
        .confirmationDialog("Bloquer \(outing?.organizerName ?? "cette personne") ?", isPresented: $confirmBlock,
                            titleVisibility: .visible) {
            Button("Bloquer", role: .destructive) {
                guard let outing else { return }
                Task { await model.block(outing.organizerID) }
            }
        } message: {
            Text("Vous ne verrez plus ses sorties et elle ne verra plus les vôtres. Vous pourrez la débloquer depuis la liste des sorties.")
        }
        .task(id: model.revision) { await loadExtras() }
    }

    private func loadExtras() async {
        participants = await model.participants(of: outingID)
        updates = await model.updates(of: outingID)
    }

    @ViewBuilder
    private func content(_ outing: OutingDTO) -> some View {
        let isOrganizer = outing.organizerID == model.userID
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    if outing.status == .cancelled {
                        Label("Sortie annulée", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.truffloDanger)
                            .accessibilityIdentifier("outing.cancelled")
                    }
                    Text(outing.meetingPoint)
                        .font(.truffloScreenTitle)
                        .foregroundStyle(Color.truffloForest)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("\(OutingFormatting.day(outing.startsAt)), \(OutingFormatting.timeRange(outing))",
                          systemImage: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.truffloCharcoal)
                    Label("\(outing.organizerName) organise, \(OutingFormatting.duration(outing.durationMinutes))",
                          systemImage: "person")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.truffloSlate)
                    Label(OutingFormatting.places(outing), systemImage: "pawprint")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.truffloForest)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.89, green: 0.94, blue: 0.90), in: Capsule())
                        .padding(.top, 2)
                }

                CommunityErrorLine()

                if outing.myStatus == .accepted, OutingFormatting.hasEnded(outing), outing.status == .published {
                    attendanceSection(outing)
                }

                if !updates.isEmpty { updatesSection }

                if !outing.rules.isEmpty {
                    section("Règles de l'organisateur") {
                        Text(outing.rules).foregroundStyle(Color.truffloCharcoal)
                    }
                }

                if !participants.isEmpty { participantsSection(outing, isOrganizer: isOrganizer) }

                section("Où et quand") {
                    Text("Le point de rendez-vous est un lieu public choisi par l'organisateur. Aucune position n'est partagée par l'app.")
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, TruffloTheme.Spacing.large)
        }
        .truffloAura()
        .safeAreaInset(edge: .bottom) { bottomAction(outing, isOrganizer: isOrganizer) }
        .sheet(isPresented: $showJoin) { JoinSheet(outing: outing) }
        .sheet(isPresented: $showReschedule) { OutingEditorView(mode: .reschedule(outing)) }
        .sheet(isPresented: $showRepropose) { OutingEditorView(mode: .create(prefill: outing)) }
        .confirmationDialog("Annuler cette sortie ?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Annuler la sortie", role: .destructive) { Task { await model.cancelOuting(outingID) } }
        } message: {
            Text("Les personnes inscrites verront qu'elle est annulée.")
        }
        .confirmationDialog("Retirer votre demande ?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Me retirer", role: .destructive) { Task { await model.withdraw(outingID) } }
        } message: {
            Text("La place est libérée. Vous pourrez redemander tant qu'il en reste.")
        }
    }

    /// Registered is not the same as having been there: asked once it is over.
    private func attendanceSection(_ outing: OutingDTO) -> some View {
        section("Y étiez-vous ?") {
            if let attended = outing.myAttended {
                Text(attended ? "Vous avez indiqué y avoir été." : "Vous avez indiqué ne pas y avoir été.")
                    .foregroundStyle(Color.truffloCharcoal)
                    .accessibilityIdentifier("outing.attendance.done")
            } else {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                    Text("Seul l'organisateur le voit.").font(.subheadline).foregroundStyle(Color.truffloSlate)
                    HStack(spacing: 10) {
                        Button("J'y étais") { Task { await model.declareAttendance(outingID, attended: true) } }
                            .buttonStyle(TruffloCapsuleStyle(prominent: true))
                            .accessibilityIdentifier("outing.attended.yes")
                        Button("Je n'y étais pas") { Task { await model.declareAttendance(outingID, attended: false) } }
                            .buttonStyle(TruffloCapsuleStyle(prominent: false))
                            .accessibilityIdentifier("outing.attended.no")
                    }
                }
            }
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
            .accessibilityIdentifier("outing.updates")
        }
    }

    private func participantsSection(_ outing: OutingDTO, isOrganizer: Bool) -> some View {
        let shown = participants.filter { isOrganizer || $0.status == .accepted }
        let pending = shown.filter { $0.status == .requested }
        let accepted = shown.filter { $0.status == .accepted }
        return VStack(alignment: .leading, spacing: 14) {
            if isOrganizer && !pending.isEmpty {
                section("Demandes à traiter") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(pending) { person in
                            HStack(alignment: .center) {
                                personLine(person)
                                Spacer(minLength: TruffloTheme.Spacing.xSmall)
                                Button("Refuser") { Task { await model.decide(outingID, userID: person.userID, accept: false) } }
                                    .buttonStyle(TruffloCapsuleStyle(prominent: false))
                                    .accessibilityIdentifier("outing.decline.\(person.displayName)")
                                Button("Accepter") { Task { await model.decide(outingID, userID: person.userID, accept: true) } }
                                    .buttonStyle(TruffloCapsuleStyle(prominent: true))
                                    .accessibilityIdentifier("outing.accept.\(person.displayName)")
                            }
                        }
                    }
                }
            }
            if !accepted.isEmpty {
                section(isOrganizer ? "Participants" : (OutingFormatting.hasEnded(outing) ? "Qui était inscrit" : "Qui vient")) {
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

    private func personLine(_ person: OutingParticipantDTO) -> some View {
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
    private func bottomAction(_ outing: OutingDTO, isOrganizer: Bool) -> some View {
        if isOrganizer {
            organizerBar(outing)
        } else {
            VStack(spacing: TruffloTheme.Spacing.xSmall) {
                if OutingFormatting.canRequest(outing) {
                    Button { showJoin = true } label: {
                        Text("Demander à venir")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color.truffloForest)
                    .accessibilityIdentifier("outing.request")
                } else if outing.myStatus == .requested || outing.myStatus == .accepted,
                          outing.status == .published, !OutingFormatting.hasEnded(outing) {
                    VStack(spacing: 2) {
                        Text(OutingFormatting.myStatus(outing) ?? "")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.truffloForest)
                        Button(outing.myStatus == .accepted ? "Me retirer" : "Retirer ma demande") { confirmWithdraw = true }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("outing.withdraw")
                    }
                    .frame(maxWidth: .infinity)
                } else if let status = OutingFormatting.myStatus(outing) {
                    Text(status).font(.headline).foregroundStyle(Color.truffloSlate)
                } else if outing.humanPlacesLeft == 0 {
                    Text("Cette sortie est complète").font(.headline).foregroundStyle(Color.truffloSlate)
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.vertical, TruffloTheme.Spacing.xSmall)
            .truffloBottomBarFade()
        }
    }

    @ViewBuilder
    private func organizerBar(_ outing: OutingDTO) -> some View {
        VStack(spacing: TruffloTheme.Spacing.xxSmall) {
            if OutingFormatting.hasEnded(outing) || outing.status != .published {
                Button { showRepropose = true } label: {
                    Text("Reproposer cette sortie")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Color.truffloForest)
                .accessibilityIdentifier("outing.repropose")
            } else {
                Text("Vous organisez cette sortie")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.truffloForest)
                HStack(spacing: TruffloTheme.Spacing.large) {
                    Button("Changer l'heure ou le lieu") { showReschedule = true }
                        .accessibilityIdentifier("outing.reschedule")
                    Button("Annuler la sortie", role: .destructive) { confirmCancel = true }
                        .accessibilityIdentifier("outing.cancel")
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TruffloTheme.Spacing.screen)
        .padding(.vertical, TruffloTheme.Spacing.xSmall)
        .truffloBottomBarFade()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TruffloSectionTitle(title)
            content()
        }
        .truffloBoardCard()
    }
}

/// Choose which dogs come, or come without one. A dog added here is the name
/// the others will see, and nothing else of the household's dog.
struct JoinSheet: View {
    let outing: OutingDTO
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
                            .buttonStyle(TruffloPressStyle())
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
                            await model.requestToJoin(outing.id, dogIDs: Array(chosen))
                            if model.errorMessage == nil { dismiss() }
                        }
                    } label: {
                        Text(chosen.isEmpty ? "Demander à venir sans chien" : "Envoyer la demande")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
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
