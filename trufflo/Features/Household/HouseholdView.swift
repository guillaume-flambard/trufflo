import AuthenticationServices
import SwiftData
import SwiftUI

/// Réglages > Foyer partagé (PRD F08). Three states: not signed in, signed in
/// without a household, member. Each one says plainly what leaves the iPhone
/// and what never does, before anything leaves it.
@MainActor
struct HouseholdView: View {
    @Environment(HouseholdModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query private var households: [HouseholdRecord]
    @Query(sort: \HouseholdMemberRecord.displayName) private var members: [HouseholdMemberRecord]
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]

    @State private var rawNonce = ""
    @State private var displayName = ""
    @State private var householdName = ""
    @State private var code = ""
    @State private var joining: (household: HouseholdDTO, dogs: [RemoteDogDTO])?
    @State private var inviteRole: HouseholdRole = .contributor
    @State private var invite: String?
    @State private var confirmLeave = false
    @State private var resumable: HouseholdDTO?

    private var household: HouseholdRecord? { households.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    if let household {
                        memberContent(household)
                    } else if !model.isAvailable {
                        Text("Le foyer partagé n'est pas disponible dans ce mode de test.")
                            .truffloSecondaryText()
                    } else if let joining {
                        JoinDogsStep(household: joining.household, householdDogs: joining.dogs,
                                     localDogs: dogs, displayName: $displayName) { links in
                            Task {
                                await model.completeJoin(joining.household, displayName: cleanName, links: links)
                                if model.errorMessage == nil { self.joining = nil }
                            }
                        }
                    } else if model.isSignedIn {
                        noHouseholdContent
                    } else {
                        signedOutContent
                    }

                    if let error = model.errorMessage {
                        Text(error)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.truffloDanger)
                            .accessibilityIdentifier("household.error")
                    }
                    if model.isBusy { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, TruffloTheme.Spacing.large)
                .padding(.vertical, TruffloTheme.Spacing.medium)
                .disabled(model.isBusy)
            }
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationTitle("Foyer partagé")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .task {
                await model.refreshSessionState()
                await model.syncNow()
                resumable = await model.householdToResume()
            }
            .onChange(of: model.isSignedIn) { _, signedIn in
                guard signedIn else { resumable = nil; return }
                Task { resumable = await model.householdToResume() }
            }
            .onChange(of: model.suggestedName) { _, name in if displayName.isEmpty { displayName = name } }
        }
    }

    private var cleanName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Not signed in

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
            Text("Partagez le journal de vos chiens avec les personnes qui les promènent aussi.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.truffloCharcoal)
            whatIsShared
            SignInWithAppleButton(.signIn) { request in
                rawNonce = AppleNonce.make()
                request.requestedScopes = [.fullName]
                request.nonce = AppleNonce.hashed(rawNonce)
            } onCompletion: { result in
                guard case .success(let authorization) = result,
                      let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let token = String(data: tokenData, encoding: .utf8) else {
                    if case .failure(let error) = result,
                       (error as? ASAuthorizationError)?.code != .canceled {
                        model.errorMessage = "La connexion avec Apple n'a pas abouti."
                    }
                    return
                }
                Task { await model.signIn(appleIDToken: token, rawNonce: rawNonce, givenName: credential.fullName?.givenName) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .accessibilityIdentifier("household.signin")
            Text("Tant que vous ne créez ni ne rejoignez de foyer, rien ne quitte cet iPhone.")
                .truffloSecondaryText()
        }
    }

    /// The promise, in two short lists (DATA-CONTRACTS §5, spec S2).
    private var whatIsShared: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            fact("checkmark.circle", "Partagé avec le foyer",
                 "Le nom, la race et l'âge des chiens. Pour chaque balade : quand, combien de temps, la distance mesurée, qui l'a enregistrée.")
            fact("lock", "Reste sur cet iPhone",
                 "Les tracés et les lieux, les notes, les photos, le sexe et les préférences des chiens.")
        }
        .padding(TruffloTheme.Spacing.medium)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func fact(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
            Image(systemName: icon).foregroundStyle(Color.truffloForest).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.truffloCharcoal)
                Text(text).font(.subheadline).foregroundStyle(Color.truffloSlate)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Signed in, no household

    private var noHouseholdContent: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
            if let resumable {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                    WalkSectionTitle("Vous êtes déjà membre de « \(resumable.name) »")
                    Text("Cet iPhone l'avait oublié. Reprenez-le pour retrouver ses balades.")
                        .truffloSecondaryText()
                    Button {
                        Task { joining = await model.resume(resumable) }
                    } label: {
                        Text("Reprendre ce foyer").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(cleanName.isEmpty)
                    .accessibilityIdentifier("household.resume")
                }
            }
            whatIsShared
            field("Votre prénom pour le foyer") {
                TextField("Prénom", text: $displayName)
                    .textContentType(.givenName)
                    .accessibilityIdentifier("household.displayName")
                    .modifier(FormFieldStyle())
            }

            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                WalkSectionTitle("Créer un foyer")
                TextField("Nom du foyer, par exemple « Maison »", text: $householdName)
                    .accessibilityIdentifier("household.name")
                    .modifier(FormFieldStyle())
                Button {
                    Task { await model.create(name: householdName.trimmingCharacters(in: .whitespacesAndNewlines), displayName: cleanName) }
                } label: {
                    Text("Créer et partager mon journal").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .disabled(cleanName.isEmpty || householdName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("household.create")
            }

            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                WalkSectionTitle("Rejoindre un foyer")
                TextField("Code reçu", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .accessibilityIdentifier("household.code")
                    .modifier(FormFieldStyle())
                Button {
                    Task { joining = await model.accept(code: code) }
                } label: {
                    Text("Rejoindre").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glass)
                .disabled(cleanName.isEmpty || code.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("household.join")
            }

            Button("Se déconnecter") { Task { await model.signOut() } }
                .font(.subheadline)
                .frame(minHeight: 44)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Color.truffloSlate)
            content()
        }
    }

    // MARK: - Member

    private func memberContent(_ household: HouseholdRecord) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                Text(household.name)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.truffloForest)
                Text("Vous êtes \(household.myRole.label.lowercased()), sous le nom « \(household.myDisplayName) ».")
                    .truffloSecondaryText()
            }

            VStack(alignment: .leading, spacing: 0) {
                WalkSectionTitle("Membres")
                ForEach(members) { member in
                    WalkFactRow(member.userID == household.myUserID ? "\(member.displayName) (vous)" : member.displayName,
                                member.role.label)
                }
            }

            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                WalkSectionTitle("Synchronisation")
                Text(syncLine(household)).truffloSecondaryText()
                if let error = household.lastError, model.errorMessage == nil {
                    Text(error).font(.subheadline).foregroundStyle(Color.truffloDanger)
                }
                Button("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.syncNow() }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("household.sync")
            }

            if household.myRole == .owner {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                    WalkSectionTitle("Inviter")
                    Picker("Rôle de la personne invitée", selection: $inviteRole) {
                        Text("Contributeur").tag(HouseholdRole.contributor)
                        Text("Lecteur").tag(HouseholdRole.reader)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("household.inviteRole")
                    Text(inviteRole == .contributor
                         ? "Ajoute ses balades et corrige les siennes."
                         : "Consulte le journal du foyer, sans rien ajouter.")
                        .truffloSecondaryText()
                    if let invite {
                        Text(invite)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .modifier(FormFieldStyle())
                            .accessibilityIdentifier("household.inviteCode")
                        ShareLink(item: "Rejoins le foyer « \(household.name) » dans Trufflo avec ce code : \(invite)") {
                            Label("Envoyer le code", systemImage: "square.and.arrow.up")
                        }
                        Text("Valable 7 jours, une seule fois.").truffloSecondaryText()
                    } else {
                        Button("Créer un code d'invitation", systemImage: "person.badge.plus") {
                            Task { invite = await model.invite(role: inviteRole) }
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("household.invite")
                    }
                }
                .onChange(of: inviteRole) { invite = nil }
            }

            Button("Quitter le foyer", role: .destructive) { confirmLeave = true }
                .frame(minHeight: 44)
                .accessibilityIdentifier("household.leave")
                .confirmationDialog("Quitter « \(household.name) » ?", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("Quitter le foyer", role: .destructive) { Task { await model.leave() } }
                } message: {
                    Text("Les balades reçues des autres membres disparaissent de cet iPhone. Votre journal reste intact. Ce que vous avez partagé reste visible du foyer.")
                }
        }
    }

    private func syncLine(_ household: HouseholdRecord) -> String {
        guard let last = household.lastSyncAt else { return "Pas encore synchronisé." }
        return "Dernière synchronisation : \(WalkFormatting.relativeDayAndTime(last))."
    }
}

/// Joining: say which local dog is which dog of the household, so the same
/// dog is not counted twice (spec S8). The default is "a new dog of the
/// household"; nothing is linked by name similarity behind the person's back.
private struct JoinDogsStep: View {
    let household: HouseholdDTO
    let householdDogs: [RemoteDogDTO]
    let localDogs: [DogRecord]
    @Binding var displayName: String
    let join: ([UUID: UUID?]) -> Void

    @State private var links: [UUID: UUID?] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
            Text("Rejoindre « \(household.name) »")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.truffloForest)
            if localDogs.isEmpty {
                Text("Vous n'avez pas encore de chien sur cet iPhone : vous verrez ceux du foyer dans le journal.")
                    .truffloSecondaryText()
            } else if householdDogs.isEmpty {
                Text("Le foyer n'a pas encore de chien : les vôtres y entreront tels quels.")
                    .truffloSecondaryText()
            } else {
                Text("Certains de vos chiens sont peut-être déjà dans le foyer. Dites lesquels, pour que leurs balades ne soient pas comptées deux fois.")
                    .truffloSecondaryText()
                ForEach(localDogs) { dog in
                    HStack {
                        TruffloDogPortrait(name: dog.name, photoData: dog.photoData, diameter: 36)
                        Text(dog.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Picker(dog.name, selection: binding(for: dog.id)) {
                            Text("Nouveau dans le foyer").tag(UUID?.none)
                            ForEach(householdDogs, id: \.id) { remote in
                                Text("C'est \(remote.name)").tag(UUID?.some(remote.id))
                            }
                        }
                        .accessibilityIdentifier("household.link.\(dog.name)")
                    }
                    .padding(TruffloTheme.Spacing.small)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            Button {
                var all: [UUID: UUID?] = [:]
                for dog in localDogs { all[dog.id] = links[dog.id] ?? nil }
                join(all)
            } label: {
                Text("Rejoindre le foyer").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("household.join.confirm")
        }
    }

    private func binding(for id: UUID) -> Binding<UUID?> {
        Binding(get: { links[id] ?? nil }, set: { links[id] = $0 })
    }
}
