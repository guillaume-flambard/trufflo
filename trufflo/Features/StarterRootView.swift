import SwiftUI
import SwiftData

/// Distinct wrappers so a dog UUID and a walk UUID can never resolve to the
/// wrong detail screen from the same navigation value.
private struct DogRoute: Hashable { let id: UUID }
struct WalkRoute: Hashable { let id: UUID }

private enum ActiveWalkCover: Identifiable {
    case resume(UUID)
    case start([UUID])

    var id: String {
        switch self {
        case .resume(let walkID): return "resume-\(walkID.uuidString)"
        case .start: return "start"
        }
    }
}

/// UI tests launch with `--uitesting`, the same flag the app already uses to
/// pick an in-memory store. Onboarding must never cover them.
private let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")

@MainActor
struct StarterRootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]
    @Query(sort: \WalkRecord.startedAt, order: .reverse) private var walks: [WalkRecord]
    @Query private var links: [WalkDogRecord]
    @Query private var routines: [RoutineRecord]
    @Query private var sharedWalks: [SharedWalkRecord]
    @Query private var householdMembers: [HouseholdMemberRecord]
    @Query private var dogLinks: [DogLinkRecord]
    @Query private var walkPhotos: [WalkPhotoRecord]
    @Query(sort: \PlannedWalkRecord.date) private var plans: [PlannedWalkRecord]
    @State private var showPlan = false
    @Environment(HouseholdModel.self) private var household
    @Environment(CommunityModel.self) private var community: CommunityModel?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHousehold = false
    @State private var showDogForm = false
    @State private var showWalkForm = false
    @State private var activeWalkCover: ActiveWalkCover?
    @State private var showEraseConfirmation = false
    @State private var showDeleteAccount = false
    @State private var accountDeleted = false
    @State private var showDeleteAccountError = false
    @State private var storageError = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboardingSheet = false
    @State private var openDogFormAfterOnboarding = false
    @State private var startBlock: LocationBlock?
    @State private var exportFile: SharedFile?
    @State private var showNewWalk = false
    @State private var startTaps = 0
    /// One namespace per stack: a walk shown on Today and in the Journal at once
    /// would otherwise be two sources for the same zoom.
    @Namespace private var todayZoom
    @Namespace private var journalZoom
    @State private var journalFilter = JournalFilter()
    /// `--demo-tab=N` (UI test runs only) opens a tab directly, for screen captures.
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("--uitesting")
        ? ProcessInfo.processInfo.arguments.lazy.compactMap { $0.hasPrefix("--demo-tab=") ? Int($0.dropFirst(11)) : nil }.first ?? 0
        : 0
    @State private var exportError: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The journal's counts, the week, the last and the live balade, read in one
    /// place (`JournalFacts`) so Today, the dog list and the Journal agree.
    private var facts: JournalFacts { JournalFacts(walks: walks, links: links) }

    private var liveWalk: WalkRecord? {
        facts.liveWalkID.flatMap { id in walks.first { $0.id == id } }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                todayContent
                .navigationTitle(dogs.isEmpty ? "Aujourd'hui" : "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .truffloScreen()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Réglages", systemImage: "gearshape") {
                            Button("Foyer partagé", systemImage: "person.2") {
                                selectedTab = 2
                            }
                            .accessibilityIdentifier("household.open")
                            Button("Exporter le journal", systemImage: "square.and.arrow.up") {
                                exportJournal()
                            }
                            .accessibilityIdentifier("journal.export")
                            Button("Revoir l'introduction", systemImage: "sparkles") {
                                showOnboardingSheet = true
                            }
                            if household.isSignedIn {
                                Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right") {
                                    Task { await household.signOut() }
                                }
                                Button("Supprimer mon compte", systemImage: "person.crop.circle.badge.xmark",
                                       role: .destructive) {
                                    showDeleteAccount = true
                                }
                            }
                            Button("Effacer toutes les données", systemImage: "trash", role: .destructive) {
                                showEraseConfirmation = true
                            }
                        }
                    }
                }
                .navigationDestination(for: WalkRoute.self) { WalkDetailView(walkID: $0.id).navigationTransition(.zoom(sourceID: $0.id, in: todayZoom)) }
                .navigationDestination(for: DogRoute.self) { DogDetailView(dogID: $0.id) }
                .navigationDestination(for: SharedWalkRoute.self) { SharedWalkDetailView(walkID: $0.id) }
            }
            .tabItem { Label("Accueil", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                journalContent
                .navigationTitle("Journal")
                .truffloAura()
                .truffloScreen()
                // The photo head carries the title and the "+"; the bar only comes
                // back for the empty journal, which has no head.
                .toolbarVisibility(journalHasList ? .hidden : .automatic, for: .navigationBar)
                .toolbar {
                    if !journalHasList && !dogs.isEmpty && liveWalk == nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Ajouter une balade", systemImage: "plus") { showWalkForm = true }
                                .accessibilityIdentifier("walk.manual.add")
                        }
                    }
                }
                .navigationDestination(for: WalkRoute.self) { WalkDetailView(walkID: $0.id).navigationTransition(.zoom(sourceID: $0.id, in: journalZoom)) }
                .navigationDestination(for: DogRoute.self) { DogDetailView(dogID: $0.id) }
                .navigationDestination(for: SharedWalkRoute.self) { SharedWalkDetailView(walkID: $0.id) }
            }
            .tabItem { Label("Journal", systemImage: "book.fill") }
            .tag(1)

            // The foyer, a tab of its own (2026-10-07 mock-up) rather than a sheet
            // behind the settings.
            HouseholdView(showsCloseButton: false, onSeeJournal: { selectedTab = 1 })
                .tabItem { Label("Foyer", systemImage: "person.3.fill") }
                .tag(2)

            dogsTab
            .tabItem { Label("Chiens", systemImage: "pawprint.fill") }
            .tag(3)

            if let community {
                NavigationStack {
                    CommunityRootView()
                }
                .environment(community)
                .tabItem { Label("Sorties", systemImage: "figure.walk") }
                .tag(4)
            }
        }
        .tint(Color.truffloForest)
        // The system tab bar: Liquid Glass, its own animations, and it folds away
        // while a long screen scrolls (Apple, *Adopting Liquid Glass*).
        .tabBarMinimizeBehavior(.onScrollDown)
        // Full screen, as in the mock-up: the form is a page of its own.
        .fullScreenCover(isPresented: $showDogForm) { DogFormView() }
        .sheet(isPresented: $showHousehold) { HouseholdView() }
        // https://trufflo.memolabs.dev/rejoindre/<code> (B-REQ-02, ADR 0009).
        // Anything else that reaches the app is ignored.
        .onOpenURL { url in
            guard let code = InviteLink.code(in: url) else { return }
            household.pendingInviteCode = code
            showHousehold = true
        }
        .task {
            // The daily tips are read without an account (`daily_tips`).
            if let client = household.client { await DailyTipsRemote.refresh(client: client) }
            await household.refreshSessionState()
            await household.syncNow()
            await household.startLiveUpdates()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    if let client = household.client { await DailyTipsRemote.refresh(client: client) }
                    await household.syncNow()
                    await household.startLiveUpdates()
                }
            case .background:
                Task { await household.stopLiveUpdates() }
            default:
                break
            }
        }
        .sheet(isPresented: $showWalkForm) { ManualWalkFormView(dogs: dogs) }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Export impossible", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("Fermer", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(item: $startBlock) { block in
            StartBlockedSheet(block: block,
                              openSettings: {
                                  startBlock = nil
                                  if let url = URL(string: UIApplication.openSettingsURLString) {
                                      UIApplication.shared.open(url)
                                  }
                              },
                              addManually: {
                                  startBlock = nil
                                  Task { @MainActor in
                                      try? await Task.sleep(for: .milliseconds(400))
                                      showWalkForm = true
                                  }
                              },
                              dismiss: { startBlock = nil })
        }
        .modifier(NewWalkCover(isPresented: $showNewWalk, dogs: dogs,
                               onStart: { ids in activeWalkCover = .start(ids) },
                               onManual: { showWalkForm = true },
                               onAddDog: { showDogForm = true }))
        .fullScreenCover(item: $activeWalkCover) { cover in
            switch cover {
            case .resume(let walkID):
                ActiveWalkView(modelContainer: context.container, existingWalkID: walkID)
            case .start(let dogIDs):
                ActiveWalkView(modelContainer: context.container, dogIDs: dogIDs)
            }
        }
        .fullScreenCover(isPresented: $showOnboardingSheet, onDismiss: {
            // The form opens once the cover is gone: presenting a sheet while
            // the cover is still on screen is dropped by SwiftUI.
            if openDogFormAfterOnboarding {
                openDogFormAfterOnboarding = false
                showDogForm = true
            }
        }) {
            let exit = OnboardingExit(hasDogs: !dogs.isEmpty)
            OnboardingView(exit: exit) { tookFinalAction in
                hasCompletedOnboarding = true
                openDogFormAfterOnboarding = tookFinalAction && exit == .addFirstDog
                showOnboardingSheet = false
            }
        }
        .onAppear {
            if !isUITesting && !hasCompletedOnboarding {
                showOnboardingSheet = true
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--show-onboarding") { showOnboardingSheet = true }
            if ProcessInfo.processInfo.arguments.contains("--open-household") { showHousehold = true }
            #endif
        }
        .confirmationDialog("Supprimer votre compte Trufflo ?",
                            isPresented: $showDeleteAccount, titleVisibility: .visible) {
            Button("Supprimer mon compte", role: .destructive) {
                Task {
                    accountDeleted = await household.deleteAccount()
                    showDeleteAccountError = !accountDeleted
                }
            }
        } message: {
            Text("Votre compte et ce que le serveur garde pour vous sont supprimés : vos balades partagées, votre nom dans le foyer. Le journal de cet iPhone reste.")
        }
        .alert("Compte supprimé", isPresented: $accountDeleted) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Votre compte n'existe plus. Votre journal reste sur cet iPhone.")
        }
        .alert("Suppression impossible", isPresented: Binding(
            get: { household.errorMessage != nil && showDeleteAccountError },
            set: { if !$0 { showDeleteAccountError = false } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(household.errorMessage ?? "")
        }
        .confirmationDialog("Effacer le journal et les chiens de cet iPhone ?",
                            isPresented: $showEraseConfirmation, titleVisibility: .visible) {
            Button("Tout effacer", role: .destructive, action: eraseAll)
        } message: {
            Text(sharedWalks.isEmpty && dogLinks.isEmpty
                 ? "Cette suppression locale ne peut pas être annulée dans le starter."
                 : "Cette suppression locale ne peut pas être annulée. Ce que vous avez déjà partagé avec le foyer y reste visible.")
        }
        .alert("Enregistrement impossible", isPresented: $storageError) {
            Button("Fermer", role: .cancel) {}
        } message: {
            Text("La modification n'a pas été enregistrée. Les données précédentes ont été conservées.")
        }
    }

    // MARK: - Journal

    @ViewBuilder
    private var journalContent: some View {
        let completed = walks.filter { $0.phase == .completed }
        let shown = completed.filter { walk in
            journalFilter.includes(isTracked: walk.source != .manual,
                                   hasPhotos: walkPhotos.contains { $0.walkID == walk.id })
                && journalFilter.includes(date: walk.endedAt ?? walk.startedAt,
                                          dogIDs: Set(links.filter { $0.walkID == walk.id }.map(\.dogID)))
        }
        // As in the mock-up, the Journal lists my balades; the foyer's are on the
        // Foyer tab and in the latest-walk block of Today.
        let sharedShown: [JournalTimelineView.SharedEntry] = []
        if completed.isEmpty {
            ScrollView {
                LostHouseholdNotice()
                // "Journal (état vide)" of the 2026-10-07 board.
                TruffloEmptyScene(picture: .journal,
                                  title: "Aucune balade pour l'instant",
                                  message: "Vos promenades apparaîtront ici. Commencez une balade pour créer votre premier souvenir.",
                                  buttonTitle: "Démarrer une balade", buttonIcon: "play.fill",
                                  buttonIdentifier: "journal.start",
                                  action: { selectedTab = 0; startWalk() })
                    .padding(.top, 120)
            }
        } else if shown.isEmpty && sharedShown.isEmpty {
            TruffloNotice(title: "Aucune balade pour ce filtre",
                          message: "Aucune balade ne correspond au chien et à la période choisis.",
                          actionTitle: "Tout afficher") { journalFilter = JournalFilter() }
        } else {
            JournalTimelineView(walks: shown, shared: sharedShown,
                                filterSummary: journalFilter.isActive ? filterSummary(count: shown.count + sharedShown.count) : nil,
                                // My balades only, the figure of Today (decision D2): the
                                // foyer's are listed but not counted, so "cette semaine"
                                // reads the same number on both screens.
                                weekCount: facts.week.walkCount,
                                zoom: journalZoom,
                                rowDestination: { WalkRoute(id: $0) },
                                hero: nil,
                                chips: AnyView(VStack(alignment: .leading, spacing: 14) {
                                    TruffloScreenHeader(
                                        title: "Journal",
                                        subtitle: weekLine,
                                        action: liveWalk == nil
                                            ? .init(systemImage: "plus", label: "Ajouter une balade",
                                                    identifier: "walk.manual.add") { showWalkForm = true }
                                            : nil)
                                    journalChips
                                }))
        }
    }

    /// Walks of the other members, under the same filter. The dog filter
    /// speaks of a local dog; a shared walk names household dogs, so the
    /// local dog is translated through its link (spec S8, S13).
    private func sharedEntries(own completed: [WalkRecord]) -> [JournalTimelineView.SharedEntry] {
        guard !sharedWalks.isEmpty else { return [] }
        let remoteOf = Dictionary(dogLinks.map { ($0.localDogID, $0.remoteDogID) }, uniquingKeysWith: { a, _ in a })
        let localOf = Dictionary(dogLinks.map { ($0.remoteDogID, $0.localDogID) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(householdMembers.map { ($0.userID, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let mine = completed.compactMap { walk -> PossibleDuplicate.Span? in
            guard let end = walk.endedAt else { return nil }
            let dogs = Set(links.filter { $0.walkID == walk.id }.compactMap { remoteOf[$0.dogID] })
            return PossibleDuplicate.Span(start: walk.startedAt, end: end, dogs: dogs)
        }
        let flagged = PossibleDuplicate.flagged(
            others: sharedWalks.map { ($0.id, PossibleDuplicate.Span(start: $0.startedAt, end: $0.endedAt, dogs: Set($0.dogIDs))) },
            mine: mine)
        return sharedWalks
            .filter { walk in
                journalFilter.includes(date: walk.endedAt, dogIDs: Set(walk.dogIDs.compactMap { localOf[$0] }))
            }
            .map { walk in
                JournalTimelineView.SharedEntry(walk: walk,
                                                authorName: names[walk.authorID] ?? "un membre du foyer",
                                                possibleDuplicate: flagged.contains(walk.id))
            }
    }

    /// "3 balades, Oslo, 30 derniers jours": says what the filtered list is.
    private func filterSummary(count: Int) -> String {
        var parts = [String(localized: "\(count) balades")]
        if let id = journalFilter.dogID, let dog = dogs.first(where: { $0.id == id }) { parts.append(dog.name) }
        if journalFilter.period != .all { parts.append(journalFilter.period.label.lowercased()) }
        return parts.joined(separator: ", ")
    }

    private var journalHasList: Bool {
        walks.contains { $0.phase == .completed } || !sharedWalks.isEmpty
    }

    /// The line under the Journal title: this week's count, as Today counts it.
    private var weekLine: String {
        switch facts.week.walkCount {
        case 0: "Tous les souvenirs de vos balades avec \(dogNames)."
        case 1: "1 balade cette semaine"
        default: "\(facts.week.walkCount) balades cette semaine"
        }
    }

    /// Toutes, Avec GPS, Ajoutées, and the dog and period filter behind the
    /// sliders, as in the mock-up.
    private var journalChips: some View {
        HStack(spacing: TruffloTheme.Spacing.xSmall) {
            TruffloFilterChips(options: JournalFilter.Kind.allCases.map { ($0, $0.label) },
                               selection: $journalFilter.kind)
            Spacer(minLength: 0)
            journalFilterMenu
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.05), in: Circle())
        }
    }

    private var journalFilterMenu: some View {
        Menu {
            if dogs.count > 1 {
                Picker("Chien", selection: $journalFilter.dogID) {
                    Text("Tous les chiens").tag(UUID?.none)
                    ForEach(dogs) { dog in Text(dog.name).tag(UUID?.some(dog.id)) }
                }
            }
            Picker("Période", selection: $journalFilter.period) {
                ForEach(JournalFilter.Period.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if journalFilter.isActive {
                Button("Tout afficher", systemImage: "xmark.circle") { journalFilter = JournalFilter() }
            }
        } label: {
            Label("Filtrer", systemImage: "slider.horizontal.3")
        }
        .accessibilityIdentifier("journal.filter")
    }

    // MARK: - Today

    /// Today is not a list. The dog is the subject, the start button is the one
    /// action, and the last walk is read as a short passage rather than a card.
    /// Facts here are descriptive (a count, an age of the last balade) and never a
    /// target, a streak or a comparison.
    @ViewBuilder
    private var todayContent: some View {
        if dogs.isEmpty {
            ScrollView {
                // Before the first dog (2026-10-07 board, "Accueil (état vide)").
                // The button adds the dog first: a balade needs one.
                TruffloEmptyScene(picture: .walkers,
                                  title: "Prêt pour votre première balade ?",
                                  message: "Ajoutez votre chien, puis enregistrez vos promenades et gardez de beaux souvenirs.",
                                  buttonTitle: "Ajouter mon chien", buttonIcon: "plus",
                                  buttonIdentifier: "dog.add",
                                  action: { showDogForm = true },
                                  linkTitle: "Revoir l'introduction",
                                  linkAction: { showOnboardingSheet = true })
                    .padding(.top, 60)
            }
            .background {
                LinearGradient(colors: [Color(red: 0.89, green: 0.95, blue: 0.91), Color.truffloSand],
                               startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            }
        } else {
            let journal = facts
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    accueilHeader
                        .padding(.bottom, 64)

                    if let currentWalk = liveWalk {
                        liveWalkSection(currentWalk)
                    } else {
                        TruffloNextWalkCard(plan: plans.first(where: { $0.date > .now.addingTimeInterval(-3600) }),
                                            onPlan: { showPlan = true }) {
                            startButton
                        }
                    }

                    if completedWalks.isEmpty {
                        firstWalkPlaceholder
                    } else {
                        todayTiles(journal)
                    }

                    if let line = routineLine(for: dogs[0]) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Routine", systemImage: "repeat")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.truffloForest)
                            Text(line)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.truffloCharcoal)
                                .accessibilityIdentifier("today.routine")
                        }
                        .truffloBoardCard()
                    }

                    if let lastWalk = journal.lastWalkID.flatMap({ id in walks.first { $0.id == id } }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                sectionTitle("Dernière balade")
                                Spacer()
                                Button {
                                    selectedTab = 1
                                } label: {
                                    Label("Voir tout", systemImage: "chevron.right")
                                        .labelStyle(TrailingIconLabelStyle())
                                        .font(.footnote)
                                        .foregroundStyle(Color.truffloSlate)
                                }
                                .accessibilityIdentifier("today.seeJournal")
                            }
                            NavigationLink(value: WalkRoute(id: lastWalk.id)) {
                                TruffloLastWalkRow(walk: lastWalk)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: lastWalk.id, in: todayZoom)
                        }
                    }
                    householdLatestWalkSection
                    TruffloDailyTip()
                    if !completedWalks.isEmpty {
                        HouseholdPrompt(place: .today, dogName: dogNames, isSeveral: dogs.count > 1) { selectedTab = 2 }
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.bottom, TruffloTheme.Spacing.large)
            }
            .sheet(isPresented: $showPlan) {
                PlanWalkSheet(current: plans.first)
            }
            .background {
                TruffloTodayBackdrop(name: dogNames, photoData: dogs.count == 1 ? dogs[0].photoData : nil)
            }
            // No blur under the bar: the photo runs clean to the top of the screen.
            .scrollEdgeEffectHidden(true, for: .top)
        }
    }

    /// "Bonjour", the dog's name leading to its profile, and its declared facts in
    /// one chip (2026-10-07 board). Without a photo, an invitation to add one.
    private var accueilHeader: some View {
        let lead = dogs[0]
        let facts = [lead.breedKind != "unknown" ? lead.breedDescription : "", lead.ageDescription]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let greeting = Calendar.current.component(.hour, from: .now) >= 18 ? "Bonsoir" : "Bonjour"
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(greeting) 👋")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
            NavigationLink(value: DogRoute(id: lead.id)) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(dogNames)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.truffloForest)
                }
                .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.dog")
            if dogs.count == 1, !facts.isEmpty {
                Label(facts, systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.truffloCharcoal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(Color.white.opacity(0.4)), in: Capsule())
            }
            if dogs.count == 1, lead.photoData == nil {
                NavigationLink(value: DogRoute(id: lead.id)) {
                    Label("Ajouter une photo de \(lead.name)", systemImage: "camera")
                        .font(.truffloBodyHeavy)
                        .foregroundStyle(Color.truffloForest)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.addPhoto")
            }
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Breed, age and sex as chips under the name: what the person declared.
    private func heroChips(_ dog: DogRecord) -> [(icon: String?, text: String)] {
        var chips: [(icon: String?, text: String)] = []
        if dog.breedKind != "unknown" { chips.append(("pawprint.fill", dog.breedDescription)) }
        if !dog.ageDescription.isEmpty { chips.append((nil, dog.ageDescription)) }
        return chips
    }

    /// Three small glass tiles: the week's count, the week's time, and how long
    /// ago the last balade ended. Facts, never a judgement about the dog.
    private func todayTiles(_ journal: JournalFacts) -> some View {
        let week = journal.week
        let last = journal.lastWalkID.flatMap { id in walks.first { $0.id == id } }
        let ago = last.map { WalkFormatting.ago($0.endedAt ?? $0.startedAt) } ?? ""
        return HStack(spacing: 10) {
            TruffloStatTile(systemImage: "figure.walk", tint: TruffloTileInk.walks,
                            value: "\(week.walkCount)",
                            label: week.walkCount == 1 ? "balade\ncette semaine" : "balades\ncette semaine",
                            valueSize: 17, iconSize: 19)
            // The middle tile is narrower in the mock-up (105 of 358 pt).
            TruffloStatTile(systemImage: "clock", tint: TruffloTileInk.time,
                            value: week.isEmpty ? "0 min" : WalkFormatting.minutes(week.totalSeconds),
                            label: "en tout")
                .frame(width: 105)
            TruffloStatTile(systemImage: "heart.fill", tint: TruffloTileInk.last,
                            value: ago,
                            label: "dernière\nbalade",
                            isSentence: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("today.week")
    }

    /// The Chiens tab (2026-10-07 board): a title, one card per dog, and a way to
    /// add one. The empty state is the board's welcome scene.
    private var dogsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TruffloScreenHeader(
                        title: "Mes chiens",
                        subtitle: dogs.count > 1 ? "Leurs profils et leurs balades." : "Son profil et ses balades.",
                        action: .init(systemImage: "plus", label: "Ajouter un chien",
                                      identifier: "dog.add.secondary") { showDogForm = true })
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    if dogs.isEmpty {
                        TruffloEmptyScene(picture: .walkers,
                                          title: "Aucun chien pour l'instant",
                                          message: "Ajoutez votre chien pour commencer son journal.",
                                          buttonTitle: "Ajouter mon chien", buttonIcon: "plus",
                                          buttonIdentifier: "dogs.empty.add",
                                          action: { showDogForm = true })
                            .padding(.top, 40)
                    } else {
                        let journal = facts
                        ForEach(dogs) { dog in
                            NavigationLink(value: DogRoute(id: dog.id)) {
                                TruffloDogCard(dog: dog, walkCount: journal.walkCount(for: dog.id),
                                               totalSeconds: journal.totalSeconds(for: dog.id))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("dog.row.\(dog.id.uuidString)")
                        }
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.bottom, TruffloTheme.Spacing.large)
            }
            .truffloAura(photoData: nil)
            .truffloScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("Mes chiens")
            .navigationDestination(for: WalkRoute.self) { WalkDetailView(walkID: $0.id) }
            .navigationDestination(for: DogRoute.self) { DogDetailView(dogID: $0.id) }
        }
    }

    private var completedWalks: [WalkRecord] { walks.filter { $0.phase == .completed } }

    /// The latest balade another member recorded, when it is newer than mine
    /// and not the same balade (B-REQ-04, decision D2). Apart from my figures,
    /// and attributed: who, which dogs, when, how long.
    @ViewBuilder
    private var householdLatestWalkSection: some View {
        let entries = sharedEntries(own: completedWalks)
        let latest = HouseholdLatestWalk.latest(
            entries.map { .init(id: $0.walk.id, endedAt: $0.walk.endedAt, isPossibleDuplicate: $0.possibleDuplicate) },
            myLastEndedAt: completedWalks.compactMap(\.endedAt).max())
        if let id = latest, let entry = entries.first(where: { $0.walk.id == id }) {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                sectionTitle("Dernière balade du foyer")
                NavigationLink(value: SharedWalkRoute(id: entry.walk.id)) {
                    SharedWalkCard(walk: entry.walk, authorName: entry.authorName, showsDay: true)
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("today.householdLatestWalk")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.truffloSectionTitle)
            .foregroundStyle(Color.truffloForest)
            .accessibilityAddTraits(.isHeader)
    }

    /// One dog with an active routine: the chosen routine and today's count, side
    /// by side, as two facts. Several dogs, or a paused routine: nothing.
    private func routineLine(for dog: DogRecord) -> String? {
        guard dogs.count == 1,
              let record = routines.first(where: { $0.dogID == dog.id }), !record.isPaused,
              let routine = record.routine else { return nil }
        let today = facts.todayCount(for: dog.id)
        // The widget is titled "Routine": the line starts with the rhythm itself.
        return "\(routine.summary). \(routine.today(recordedWalks: today))"
    }

    private func dogSubtitle(_ lead: DogRecord) -> String {
        guard dogs.count == 1 else { return "\(dogs.count) chiens" }
        let parts = [lead.breedKind != "unknown" ? lead.breedDescription : "", lead.ageDescription]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Prêt pour la balade" : parts.joined(separator: ", ")
    }

    private var dogNames: String {
        dogs.map(\.name).formatted(.list(type: .and).locale(TruffloLocale.french))
    }

    /// A walk in progress takes the place of the start button, so a second one
    /// cannot be started by mistake. The time keeps running on screen: the
    /// stored duration covers the last checkpoint, and while recording the
    /// seconds since that checkpoint are added on top.
    ///
    /// Drawn as the same white tile as the last walk, with the same ink: a dark
    /// forest block here made Today read as two apps (2026-10-07 review).
    private func liveWalkSection(_ walk: WalkRecord) -> some View {
        let isInterrupted = walk.phase == .interrupted
        let isRecording = walk.phase == .recording
        let shape = RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                Circle()
                    .fill(isInterrupted ? Color.truffloDanger : isRecording ? Color.truffloSage : Color.truffloSlate)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Text(isInterrupted ? "Balade interrompue" : isRecording ? "Balade en cours" : "Balade en pause")
                    .font(.truffloBodyHeavy)
                    .foregroundStyle(Color.truffloForest)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = walk.confirmedSeconds
                    + (isRecording ? max(context.date.timeIntervalSince(walk.lastCheckpointAt), 0) : 0)
                HStack(alignment: .top, spacing: TruffloTheme.Spacing.xLarge) {
                    liveFigure("Durée", WalkFormatting.clock(seconds))
                    liveFigure("Distance", WalkFormatting.distance(walk.recordedPathMeters))
                }
            }
            if isInterrupted {
                Text("Données enregistrées jusqu'au dernier point.")
                    .font(.truffloMeta)
                    .foregroundStyle(Color.truffloSlate)
            }
            Button {
                activeWalkCover = .resume(walk.id)
            } label: {
                Text("Revenir à la balade")
                    .font(.truffloBodyHeavy)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.truffloForest)
            .truffloTap()
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: shape)
        .shadow(color: Color.truffloForest.opacity(0.10), radius: 18, x: 0, y: 8)
        .shadow(color: Color.truffloForest.opacity(0.05), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walk.live.banner")
    }

    private func liveFigure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.truffloMeta).foregroundStyle(Color.truffloSlate)
            Text(value)
                .font(.truffloFigure(.title))
                .monospacedDigit()
                .foregroundStyle(Color.truffloForest)
        }
    }

    /// Before the first walk: no zeros, no empty statistics, a dashed slot that
    /// says what will appear here.
    private var firstWalkPlaceholder: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
            Text(dogs.count > 1 ? "Leur première balade s'affichera ici" : "Sa première balade s'affichera ici")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.truffloForest)
            Text("Avec sa durée, son tracé, et la note que vous voudrez y laisser.")
                .font(.subheadline)
                .foregroundStyle(Color.truffloSlate)
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
            .strokeBorder(Color.truffloForest.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
    }

    /// Checks the permission before opening the live screen. A walk that cannot
    /// start is explained on Today; the live screen keeps its own check for the
    /// case where the permission changes after this one.
    private func startWalk() {
        if let unfinished = liveWalk {
            activeWalkCover = .resume(unfinished.id)
            return
        }
        guard dogs.first != nil else { return }
        let probe = CoreLocationProvider()
        switch probe.authorization {
        case .denied: startBlock = .permissionDenied
        case .restricted: startBlock = .permissionRestricted
        case .notDetermined, .authorizedWhenInUse, .authorizedAlways:
            if probe.authorization != .notDetermined && !probe.servicesAvailable {
                startBlock = .servicesUnavailable
            } else {
                // The step before the walk (2026-10-07 mock-up): which dogs, how, where.
                showNewWalk = true
            }
        }
    }

    /// The one action of the screen, anchored where the thumb rests.
    private var startButton: some View {
        Button {
            startTaps += 1
            startWalk()
        } label: {
            Label("Démarrer une balade", systemImage: "play.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(Color.truffloForest)
        .sensoryFeedback(.impact(weight: .light), trigger: startTaps)
    }

    /// Builds the archive (a summary CSV plus one GPX per recorded route) and
    /// hands it to the share sheet, where the person chooses where it goes.
    private func exportJournal() {
        do {
            let walks = try JournalRepository(context: context).exportWalks()
            exportFile = SharedFile(url: try ExportArchive.make(from: walks))
        } catch ExportArchive.Failure.nothingToExport {
            exportError = "Le journal ne contient encore aucune balade terminée."
        } catch {
            exportError = "L'export n'a pas pu être préparé. Votre journal n'a pas été modifié."
        }
    }

    private func eraseAll() {
        do {
            try JournalRepository(context: context).eraseAll()
            Task { await household.forgetSession() }
        } catch { storageError = true }
    }
}

extension LocationBlock: Identifiable {
    public var id: String { rawValue }
}

/// The start button label: icon and title, or the title alone when the text size is
/// an accessibility one and the icon would only cost a line.
private struct StartLabelStyle: LabelStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        if compact {
            configuration.title
        } else {
            Label(configuration)
        }
    }
}

/// Title first, icon after: "Voir tout >".
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

/// "Nouvelle balade" as a full-screen step; each exit waits for the cover to be
/// gone before opening the next screen, which SwiftUI would otherwise drop.
private struct NewWalkCover: ViewModifier {
    @Binding var isPresented: Bool
    let dogs: [DogRecord]
    let onStart: ([UUID]) -> Void
    let onManual: () -> Void
    let onAddDog: () -> Void

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            NewWalkView(dogs: dogs,
                        onStart: { ids in later { onStart(ids) } },
                        onManual: { later(onManual) },
                        onAddDog: { later(onAddDog) })
        }
    }

    private func later(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            action()
        }
    }
}
