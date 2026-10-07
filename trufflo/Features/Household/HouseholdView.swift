import AuthenticationServices
import SwiftData
import SwiftUI

/// Réglages > Foyer partagé (PRD F08).
///
/// Each state opens on a forest band, the same ground as the first page of
/// the introduction: the faces of the household meet there. Below it, on sand,
/// one decision at a time. What leaves the iPhone is said before anything does.
@MainActor
struct HouseholdView: View {
    @Environment(HouseholdModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query private var households: [HouseholdRecord]
    @Query(sort: \HouseholdMemberRecord.displayName) private var members: [HouseholdMemberRecord]
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]
    @Query private var shared: [SharedWalkRecord]

    @State private var rawNonce = ""
    @State private var displayName = ""
    @State private var householdName = ""
    @State private var code = ""
    @State private var path: Choice?
    @State private var joining: (household: HouseholdDTO, dogs: [RemoteDogDTO])?
    @State private var inviteRole = HouseholdRole.contributor.rawValue
    @State private var invite: String?
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var memberToRemove: HouseholdMemberRecord?
    @State private var resumable: HouseholdDTO?
    /// In the Foyer tab there is nothing to close: the sheet's close button hides.
    var showsCloseButton = true

    private enum Choice { case create, join }
    private var household: HouseholdRecord? { households.first }
    private var cleanName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // The band's aura sits behind the scroll view, so it runs up under the
            // bar as on Today and the profile.
            .background(alignment: .top) {
                TruffloDogAura(photoData: nil)
                    .frame(height: 420)
                    .ignoresSafeArea(edges: .top)
            }
            .background(Color.truffloSand.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { bottomAction }
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer", systemImage: "xmark") { dismiss() }
                    }
                }
                if path != nil, joining == nil, household == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Retour", systemImage: "chevron.left") { withAnimation { path = nil } }
                    }
                }
            }
            // The band runs up under the bar, on the same light aura as Today and the
            // profile: a forest field here made the sheet the one dark screen of the app.
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(Color.truffloForest)
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--demo-join") {
                    displayName = "Bruno"
                    joining = (HouseholdDTO(id: UUID(), name: "Maison"),
                               [RemoteDogDTO(id: UUID(), name: "Oslo", breedKind: "mixed", breedLabel: "", deletedAt: nil),
                                RemoteDogDTO(id: UUID(), name: "Lune", breedKind: "unknown", breedLabel: "", deletedAt: nil)])
                }
                #endif
                await model.refreshSessionState()
                await model.syncNow()
                resumable = await model.householdToResume()
                applyPendingInvite()
            }
            .onChange(of: model.isSignedIn) { _, signedIn in
                guard signedIn else { resumable = nil; return }
                applyPendingInvite()
                Task { resumable = await model.householdToResume() }
            }
            .onChange(of: model.pendingInviteCode) { _, _ in applyPendingInvite() }
            .onChange(of: model.suggestedName) { _, name in if displayName.isEmpty { displayName = name } }
            .disabled(model.isBusy)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let household {
            memberContent(household)
        } else if model.lostHousehold != nil {
            LostHouseholdNotice()
                .padding(TruffloTheme.Spacing.large)
        } else if !model.isAvailable {
            HouseholdBand(title: "Foyer partagé", subtitle: "Indisponible dans ce mode de test.", faces: dogFaces)
        } else if let joining {
            JoinDogsStep(household: joining.household, householdDogs: joining.dogs,
                         localDogs: dogs, links: $joinLinks)
        } else if model.isSignedIn {
            switch path {
            case .create: createStep
            case .join: joinStep
            case nil: choiceContent
            }
        } else {
            signedOutContent
        }
        errorLine
    }

    @State private var joinLinks: [UUID: UUID?] = [:]

    private var dogFaces: [HouseholdBand.Face] {
        // Real faces only: a dog without a photo, or a person not yet known,
        // gets no stand-in disc.
        dogs.filter { $0.photoData != nil }.prefix(3).map { .dog(name: $0.name, photo: $0.photoData) }
    }

    // MARK: - Bottom action, one per state

    private var bottomAction: some View {
        bottomActionContent
            .padding(.top, TruffloTheme.Spacing.small)
            .background {
                LinearGradient(colors: [Color.truffloSand.opacity(0), Color.truffloSand, Color.truffloSand],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
    }

    @ViewBuilder
    private var bottomActionContent: some View {
        if household != nil || !model.isAvailable {
            EmptyView()
        } else if let joining {
            primaryButton("Rejoindre « \(joining.household.name) »", id: "household.join.confirm",
                          enabled: !cleanName.isEmpty) {
                var links: [UUID: UUID?] = [:]
                for dog in dogs { links[dog.id] = joinLinks[dog.id] ?? nil }
                Task {
                    await model.completeJoin(joining.household, displayName: cleanName, links: links)
                    if model.errorMessage == nil { self.joining = nil; path = nil }
                }
            }
        } else if !model.isSignedIn {
            VStack(spacing: TruffloTheme.Spacing.small) {
                SignInWithAppleButton(.signIn) { request in
                    rawNonce = AppleNonce.make()
                    request.requestedScopes = [.fullName]
                    request.nonce = AppleNonce.hashed(rawNonce)
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
                .accessibilityIdentifier("household.signin")
                Text("Tant que vous ne créez ni ne rejoignez de foyer, rien ne quitte cet iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.bottom, TruffloTheme.Spacing.xSmall)
        } else if path == .create {
            primaryButton("Créer et partager mon journal", id: "household.create",
                          enabled: !cleanName.isEmpty && !householdName.trimmingCharacters(in: .whitespaces).isEmpty) {
                Task {
                    await model.create(name: householdName.trimmingCharacters(in: .whitespacesAndNewlines),
                                       displayName: cleanName)
                }
            }
        } else if path == .join {
            primaryButton("Continuer", id: "household.join",
                          enabled: !cleanName.isEmpty && !code.trimmingCharacters(in: .whitespaces).isEmpty) {
                Task { joining = await model.accept(code: code.filter { !$0.isWhitespace }) }
            }
        } else {
            EmptyView()
        }
    }

    private func primaryButton(_ title: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                if model.isBusy { ProgressView().tint(.white) }
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.truffloForest)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
        .padding(.horizontal, TruffloTheme.Spacing.screen)
        .padding(.bottom, TruffloTheme.Spacing.xSmall)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                model.errorMessage = "Apple n'a pas renvoyé d'identité. Réessayez."
                return
            }
            Task { await model.signIn(appleIDToken: token, rawNonce: rawNonce, givenName: credential.fullName?.givenName) }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                model.errorMessage = "La connexion avec Apple n'a pas abouti."
            }
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.truffloDanger)
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.top, TruffloTheme.Spacing.medium)
                .accessibilityIdentifier("household.error")
        }
    }

    // MARK: - Not signed in

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseholdBand(title: "Un journal, plusieurs promeneurs.",
                          subtitle: "Celles et ceux qui sortent vos chiens voient leurs balades, et vous les leurs.",
                          faces: dogFaces)
            SharingTerms()
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.top, TruffloTheme.Spacing.large)
        }
    }

    // MARK: - Signed in, no household

    private var choiceContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseholdBand(title: "Créer ou rejoindre.",
                          subtitle: "Un foyer à la fois. Vous pourrez le quitter quand vous voudrez.",
                          faces: dogFaces)
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
                if let resumable {
                    ChoiceCard(icon: "arrow.uturn.backward.circle", title: "Reprendre « \(resumable.name) »",
                               detail: "Vous en êtes déjà membre. Cet iPhone l'avait oublié.", emphasized: true) {
                        Task { joining = await model.resume(resumable) }
                    }
                    .accessibilityIdentifier("household.resume")
                    .disabled(cleanName.isEmpty)
                    nameField
                }
                ChoiceCard(icon: "house", title: "Créer un foyer",
                           detail: "Vos chiens et vos balades y entrent. Vous invitez ensuite qui vous voulez.") {
                    withAnimation { path = .create }
                }
                .accessibilityIdentifier("household.choose.create")
                ChoiceCard(icon: "key", title: "J'ai un code",
                           detail: "Un membre d'un foyer vous a envoyé un code d'invitation.") {
                    withAnimation { path = .join }
                }
                .accessibilityIdentifier("household.choose.join")
                Button("Se déconnecter") { Task { await model.signOut() } }
                    .font(.subheadline)
                    .foregroundStyle(Color.truffloSlate)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.top, TruffloTheme.Spacing.large)
        }
    }

    private var nameField: some View {
        FieldBlock(label: "Votre prénom, tel que le foyer le verra") {
            TextField("Prénom", text: $displayName)
                .textContentType(.givenName)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .accessibilityIdentifier("household.displayName")
        }
    }

    private var createStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseholdBand(title: "Un nom pour le foyer.",
                          subtitle: "Celui que verront les personnes que vous inviterez.",
                          faces: dogFaces)
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                FieldBlock(label: "Nom du foyer") {
                    TextField("Par exemple « Maison »", text: $householdName)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .accessibilityIdentifier("household.name")
                }
                nameField
                SharingTerms(compact: true)
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.top, TruffloTheme.Spacing.large)
        }
    }

    private var joinStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseholdBand(title: "Le code reçu.",
                          subtitle: "Valable sept jours, une seule fois.",
                          faces: dogFaces)
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                FieldBlock(label: "Code d'invitation") {
                    TextField("Collez le code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .accessibilityIdentifier("household.code")
                }
                nameField
                SharingTerms(compact: true)
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.top, TruffloTheme.Spacing.large)
        }
    }

    // MARK: - Member

    private func memberContent(_ household: HouseholdRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseholdBand(title: household.name,
                          subtitle: members.count <= 1 ? "Vous seul pour l'instant."
                              : "\(String(localized: "\(members.count) membres")), \(String(localized: "\(shared.count) balades reçues")).",
                          faces: members.map { .person($0.displayName) },
                          badge: household.myRole.label)

            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                SyncStatusCard(household: household, isBusy: model.isBusy) {
                    Task { await model.syncNow() }
                }

                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                    WalkSectionTitle("Membres")
                    VStack(spacing: 0) {
                        ForEach(Array(members.enumerated()), id: \.element.userID) { index, member in
                            let isMe = member.userID == household.myUserID
                            let row = MemberRow(name: member.displayName, role: member.role,
                                                isMe: isMe, tintIndex: index,
                                                isManageable: household.myRole == .owner && !isMe)
                            if household.myRole == .owner && !isMe {
                                // The owner manages the others from their row.
                                Menu {
                                    ForEach(HouseholdRole.allCases.filter { $0 != member.role }, id: \.self) { role in
                                        Button("Passer \(role.label.lowercased())") {
                                            Task { await model.setRole(role, of: member.userID) }
                                        }
                                    }
                                    Divider()
                                    Button("Retirer du foyer", role: .destructive) { memberToRemove = member }
                                } label: {
                                    row.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Changer son rôle ou le retirer du foyer")
                                .accessibilityIdentifier("household.member.\(member.userID.uuidString)")
                            } else {
                                row
                            }
                            if index < members.count - 1 {
                                Rectangle().fill(Color.truffloForest.opacity(0.1)).frame(height: 1)
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.truffloForest.opacity(0.1)).frame(height: 1)
                    }
                }

                if household.myRole == .owner { inviteSection(household) }

                exitSection(household)
                .confirmationDialog("Quitter « \(household.name) » ?", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("Quitter le foyer", role: .destructive) { Task { await model.leave() } }
                } message: {
                    Text("Les balades reçues des autres membres disparaissent de cet iPhone. Votre journal reste intact.")
                }
                .confirmationDialog("Supprimer « \(household.name) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Supprimer le foyer", role: .destructive) { Task { await model.deleteHousehold() } }
                } message: {
                    Text("Le foyer et ce qui y a été partagé sont effacés du serveur. Votre journal reste sur cet iPhone.")
                }
                .confirmationDialog("Retirer \(memberToRemove?.displayName ?? "ce membre") du foyer ?",
                                    isPresented: Binding(get: { memberToRemove != nil },
                                                         set: { if !$0 { memberToRemove = nil } }),
                                    titleVisibility: .visible) {
                    Button("Retirer du foyer", role: .destructive) {
                        if let member = memberToRemove { Task { await model.remove(memberID: member.userID) } }
                    }
                } message: {
                    Text("Ses nouvelles balades ne vous parviendront plus, et son iPhone oubliera le foyer à sa prochaine connexion. Ce qu'il a déjà vu reste vu.")
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.top, TruffloTheme.Spacing.large)
            .padding(.bottom, TruffloTheme.Spacing.xLarge)
        }
    }

    private func inviteSection(_ household: HouseholdRecord) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            WalkSectionTitle("Inviter quelqu'un")
            TruffloChoice(options: [(HouseholdRole.contributor.rawValue, "Contributeur"),
                                    (HouseholdRole.reader.rawValue, "Lecteur")],
                          selection: $inviteRole)
                .accessibilityIdentifier("household.inviteRole")
            Text(inviteRole == HouseholdRole.contributor.rawValue
                 ? "Ajoute ses balades et corrige les siennes."
                 : "Consulte le journal du foyer, sans rien ajouter.")
                .font(.subheadline)
                .foregroundStyle(Color.truffloSlate)
            if let invite {
                InviteTicket(code: invite, householdName: household.name)
            } else {
                Button {
                    Task { invite = await model.invite(role: HouseholdRole(rawValue: inviteRole) ?? .reader) }
                } label: {
                    Label("Créer un code d'invitation", systemImage: "person.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glass)
                .tint(Color.truffloForest)
                .accessibilityIdentifier("household.invite")
            }
        }
        .onChange(of: inviteRole) { invite = nil }
    }
}

// MARK: - Pieces

/// The band at the top of every state, on the mint aura the dog screens share:
/// who is in the picture, then the one sentence of the state. Faces overlap, the way people stand
/// together, and a dashed peach line joins dogs and people.
struct HouseholdBand: View {
    enum Face: Hashable {
        case dog(name: String, photo: Data?)
        case person(String)
    }

    let title: String
    let subtitle: String
    let faces: [Face]
    /// A second group, joined to the first by the dashed line. When nil, the
    /// faces split by kind: dogs on the left, people on the right.
    var others: [Face]? = nil
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
            if !faces.isEmpty || !(others ?? []).isEmpty {
                faceRow
                    .padding(.top, TruffloTheme.Spacing.xSmall)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                if let badge {
                    Text(badge)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.truffloForest)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white, in: Capsule())
                }
                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .foregroundStyle(Color.truffloForest)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Color.truffloSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, TruffloTheme.Spacing.screen)
        .padding(.bottom, TruffloTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var faceRow: some View {
        let dogs = others == nil ? faces.filter { if case .dog = $0 { true } else { false } } : faces
        let people = others ?? faces.filter { if case .person = $0 { true } else { false } }
        return HStack(spacing: TruffloTheme.Spacing.small) {
            cluster(dogs)
            if !dogs.isEmpty && !people.isEmpty {
                Line()
                    .stroke(Color.truffloPeach, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 7]))
                    .frame(width: 44, height: 3)
            }
            cluster(people)
        }
        .frame(height: 64)
    }

    private func cluster(_ faces: [Face]) -> some View {
        HStack(spacing: -16) {
            ForEach(Array(faces.prefix(4).enumerated()), id: \.offset) { index, face in
                Group {
                    switch face {
                    case .dog(let name, let photo):
                        TruffloDogPortrait(name: name, photoData: photo, diameter: 60)
                    case .person(let name):
                        PersonDisc(name: name, diameter: 60, tintIndex: index)
                    }
                }
                .overlay(Circle().strokeBorder(Color.truffloSand, lineWidth: 3))
                .zIndex(Double(10 - index))
            }
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// A person, by initial: mint or peach so two members never look alike side by side.
struct PersonDisc: View {
    let name: String
    var diameter: CGFloat = 44
    var tintIndex = 0

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        let fill = tintIndex % 2 == 0 ? Color.truffloMint : Color.truffloPeach
        Text(initial)
            .font(.system(size: diameter * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.truffloForest)
            .frame(width: diameter, height: diameter)
            .background(fill, in: Circle())
    }
}

/// What leaves the iPhone and what never does, as two short lists.
private struct SharingTerms: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? TruffloTheme.Spacing.small : TruffloTheme.Spacing.medium) {
            column(icon: "arrow.up.right.circle.fill", tint: Color.truffloSage, title: "Partagé avec le foyer",
                   items: ["Nom, race et âge des chiens", "Pour chaque balade : quand, combien de temps, la distance mesurée", "Qui l'a enregistrée"])
            Divider()
            column(icon: "lock.fill", tint: Color.truffloForest, title: "Reste sur cet iPhone",
                   items: ["Les tracés et les lieux", "Les notes de balade", "Les photos, le sexe et les préférences des chiens"])
        }
    }

    private func column(icon: String, tint: Color, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            HStack(spacing: TruffloTheme.Spacing.small) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.truffloForest)
            }
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline)
                    .foregroundStyle(Color.truffloCharcoal)
                    .padding(.leading, 32)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChoiceCard: View {
    let icon: String
    let title: String
    let detail: String
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: TruffloTheme.Spacing.medium) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(emphasized ? Color.white : Color.truffloForest)
                    .frame(width: 48, height: 48)
                    .background(emphasized ? Color.truffloForest : Color.truffloMint.opacity(0.6), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.truffloForest)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.truffloForest.opacity(0.4))
                    .padding(.top, 14)
            }
            .padding(.vertical, TruffloTheme.Spacing.small)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.truffloForest.opacity(0.1)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct FieldBlock<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Color.truffloSlate)
            content.modifier(FormFieldStyle())
        }
    }
}

extension HouseholdView {
    /// Places a code from an invitation link in « Rejoindre ». Signed out, it
    /// waits for the sign-in. Already in a household, it is dropped with a
    /// sentence: one household per iPhone.
    fileprivate func applyPendingInvite() {
        guard let pending = model.pendingInviteCode else { return }
        if household != nil {
            model.pendingInviteCode = nil
            model.errorMessage = "Cet iPhone fait déjà partie d'un foyer. Pour en rejoindre un autre, quittez d'abord celui-ci."
        } else if model.isSignedIn {
            model.pendingInviteCode = nil
            code = pending
            withAnimation { path = .join }
        }
    }
}

extension HouseholdView {
    /// The way out, as the server allows it: leave, name another owner first,
    /// or, alone, delete the household (B-REQ-05).
    @ViewBuilder
    fileprivate func exitSection(_ household: HouseholdRecord) -> some View {
        let exit = MembershipExit(myRole: household.myRole, roles: members.map(\.role))
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
            switch exit {
            case .leave:
                Button("Quitter le foyer", role: .destructive) { confirmLeave = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("household.leave")
                Text("Votre journal reste sur cet iPhone. Ce que vous avez partagé reste visible du foyer.")
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
            case .nameAnotherOwnerFirst:
                Text("Vous êtes le seul responsable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.truffloCharcoal)
                Text("Pour quitter le foyer, nommez d'abord un autre responsable : touchez un membre et choisissez « Passer responsable ».")
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
                    .accessibilityIdentifier("household.leave.blocked")
            case .deleteHousehold:
                Button("Supprimer le foyer", role: .destructive) { confirmDelete = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("household.delete")
                Text("Vous êtes seul dans ce foyer. Le supprimer efface ce qui a été partagé sur le serveur ; votre journal reste sur cet iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
            }
        }
    }
}

private struct MemberRow: View {
    let name: String
    let role: HouseholdRole
    let isMe: Bool
    let tintIndex: Int
    /// The owner can act on this row: say so, the row is a menu.
    var isManageable = false

    var body: some View {
        HStack(spacing: TruffloTheme.Spacing.small) {
            PersonDisc(name: name, diameter: 40, tintIndex: tintIndex)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(Color.truffloCharcoal)
                    .lineLimit(1)
                Text(isMe ? "Vous" : roleDetail).font(.footnote).foregroundStyle(Color.truffloSlate)
            }
            Spacer(minLength: TruffloTheme.Spacing.xSmall)
            TruffloBadge(role.label, style: role == .owner ? .forest : .sage)
                .fixedSize()
            if isManageable {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Color.truffloForest)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, TruffloTheme.Spacing.small)
        .accessibilityElement(children: .combine)
    }

    private var roleDetail: String {
        switch role {
        case .owner: "Invite et gère le foyer"
        case .contributor: "Ajoute ses balades"
        case .reader: "Consulte le journal"
        }
    }
}

private struct SyncStatusCard: View {
    let household: HouseholdRecord
    let isBusy: Bool
    let sync: () -> Void

    var body: some View {
        HStack(spacing: TruffloTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(household.lastError == nil ? Color.truffloSage : Color.truffloDanger)
                .symbolEffect(.rotate, isActive: isBusy)
                .frame(width: 40, height: 40)
                .background((household.lastError == nil ? Color.truffloSage : Color.truffloDanger).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color.truffloCharcoal)
                Text(detail).font(.footnote).foregroundStyle(Color.truffloSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: TruffloTheme.Spacing.xSmall)
            Button(action: sync) {
                Image(systemName: "arrow.clockwise")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.truffloForest)
                    .frame(width: 44, height: 44)
                    .background(Color.truffloMint.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Synchroniser maintenant")
            .accessibilityIdentifier("household.sync")
        }
        .padding(TruffloTheme.Spacing.medium)
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        if isBusy { return "arrow.triangle.2.circlepath" }
        return household.lastError == nil ? "checkmark" : "exclamationmark"
    }

    private var title: String {
        if isBusy { return "Synchronisation…" }
        if household.lastError != nil { return "Pas à jour" }
        return household.lastSyncAt == nil ? "Pas encore synchronisé" : "À jour"
    }

    private var detail: String {
        if let error = household.lastError { return error }
        guard let last = household.lastSyncAt else { return "La première synchronisation part à l'ouverture." }
        return "\(WalkFormatting.relativeDayAndTime(last).capitalizedFirst), en direct ensuite."
    }
}

/// The invite code as a ticket: grouped by four so it can be read aloud,
/// copied in one tap, sent with the system share sheet.
private struct InviteTicket: View {
    let code: String

    /// The link opens the app on « Rejoindre » with the code in place; the
    /// code stays in the message for someone who types it instead.
    private var shareMessage: String {
        let link = InviteLink.url(for: code).map { "\n\($0.absoluteString)" } ?? ""
        return "Rejoins le foyer « \(householdName) » dans Trufflo :\(link)\n\nOu, dans l'app, Réglages, Foyer partagé, J'ai un code, avec ce code : \(code)"
    }
    let householdName: String
    @State private var copied = false

    private var grouped: String {
        stride(from: 0, to: code.count, by: 4).map { start in
            let lower = code.index(code.startIndex, offsetBy: start)
            let upper = code.index(lower, offsetBy: min(4, code.count - start))
            return String(code[lower..<upper])
        }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            Text("Code pour « \(householdName) »")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.truffloMint)
            Text(grouped)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Code d'invitation")
                .accessibilityValue(code)
                .accessibilityIdentifier("household.inviteCode")
            Text("Valable 7 jours, une seule fois.")
                .font(.footnote)
                .foregroundStyle(Color.truffloMint)
            HStack(spacing: TruffloTheme.Spacing.small) {
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                } label: {
                    Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .tint(.white)
                ShareLink(item: shareMessage) {
                    Label("Envoyer", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.truffloPeach)
            }
        }
        .padding(TruffloTheme.Spacing.medium)
        .background(Color.truffloForest, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle().fill(Color.truffloSand).frame(width: 22, height: 22).offset(x: 11, y: 54)
        }
        .overlay(alignment: .topLeading) {
            Circle().fill(Color.truffloSand).frame(width: 22, height: 22).offset(x: -11, y: 54)
        }
    }
}

/// Joining: say which local dog is which dog of the household, so the same
/// dog is not counted twice (spec S8). The default is "new in the
/// household"; nothing is linked by name behind the person's back.
private struct JoinDogsStep: View {
    let household: HouseholdDTO
    let householdDogs: [RemoteDogDTO]
    let localDogs: [DogRecord]
    @Binding var links: [UUID: UUID?]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseholdBand(title: "Qui est qui ?",
                          subtitle: subtitle,
                          faces: localDogs.filter { $0.photoData != nil }.prefix(3).map { .dog(name: $0.name, photo: $0.photoData) })
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
                ForEach(localDogs) { dog in
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        HStack(spacing: TruffloTheme.Spacing.small) {
                            if let photo = dog.photoData {
                                TruffloDogPortrait(name: dog.name, photoData: photo, diameter: 44)
                            }
                            Text(dog.name)
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.truffloForest)
                        }
                        WrappingRow(spacing: TruffloTheme.Spacing.xSmall) {
                            Group {
                                chip("Nouveau dans le foyer", isOn: (links[dog.id] ?? nil) == nil) {
                                    links[dog.id] = UUID?.none
                                }
                                ForEach(householdDogs, id: \.id) { remote in
                                    chip("C'est \(remote.name)", isOn: (links[dog.id] ?? nil) == remote.id) {
                                        links[dog.id] = remote.id
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("household.link.\(dog.name)")
                    }
                    .padding(.vertical, TruffloTheme.Spacing.small)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.truffloForest.opacity(0.1)).frame(height: 1)
                    }
                }
                if localDogs.isEmpty {
                    Text("Vous verrez les chiens du foyer dans le journal.")
                        .font(.subheadline).foregroundStyle(Color.truffloSlate)
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.top, TruffloTheme.Spacing.large)
        }
    }

    private var subtitle: String {
        if localDogs.isEmpty { return "Vous n'avez pas encore de chien sur cet iPhone." }
        if householdDogs.isEmpty { return "« \(household.name) » n'a pas encore de chien : les vôtres y entrent tels quels." }
        return "Dites lesquels de vos chiens sont déjà dans « \(household.name) », pour ne pas compter leurs balades deux fois."
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .foregroundStyle(isOn ? Color.white : Color.truffloCharcoal)
                .background(isOn ? Color.truffloForest : Color.truffloSand, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.truffloForest.opacity(isOn ? 0 : 0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Lays its children out left to right and wraps to a new line when the
/// next one does not fit, so a choice is never cut at the edge of the screen.
struct WrappingRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
