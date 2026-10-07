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
    @Environment(HouseholdModel.self) private var household
    @Environment(CommunityModel.self) private var community: CommunityModel?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHousehold = false
    @State private var showDogForm = false
    @State private var showWalkForm = false
    @State private var activeWalkCover: ActiveWalkCover?
    @State private var showEraseConfirmation = false
    @State private var storageError = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboardingSheet = false
    @State private var openDogFormAfterOnboarding = false
    @State private var startBlock: LocationBlock?
    @State private var exportFile: SharedFile?
    @State private var showWhoIsWalking = false
    @State private var startTaps = 0
    /// One namespace per stack: a walk shown on Today and in the Journal at once
    /// would otherwise be two sources for the same zoom.
    @Namespace private var todayZoom
    @Namespace private var journalZoom
    @State private var journalFilter = JournalFilter()
    @State private var selectedTab = 0
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
            .tabItem { Label("Aujourd'hui", systemImage: "house.fill") }
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

            NavigationStack {
                List {
                    if dogs.isEmpty {
                        TruffloEmptyStateView(
                            imageName: "EmptyDog",
                            title: "Aucun chien",
                            description: "Ajoutez votre chien pour commencer son journal.",
                            buttonTitle: "Ajouter un chien",
                            action: { showDogForm = true }
                        )
                        // On the sand, not in a white card: a card holds an object.
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        let journal = facts
                        ForEach(dogs) { dog in
                            // The link sits behind the card so the list draws no
                            // disclosure chevron outside it.
                            dogCard(dog, walkCount: journal.walkCount(for: dog.id),
                                    totalSeconds: journal.totalSeconds(for: dog.id))
                                .background(NavigationLink(value: DogRoute(id: dog.id)) { EmptyView() }.opacity(0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: TruffloTheme.Spacing.screen, bottom: 6, trailing: TruffloTheme.Spacing.screen))
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Mes chiens")
                .truffloAura()
                .truffloScreen()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Ajouter", systemImage: "plus") { showDogForm = true }
                            .accessibilityIdentifier("dog.add.secondary")
                    }
                }
                .navigationDestination(for: WalkRoute.self) { WalkDetailView(walkID: $0.id) }
                .navigationDestination(for: DogRoute.self) { DogDetailView(dogID: $0.id) }
            }
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
            await household.refreshSessionState()
            await household.syncNow()
            await household.startLiveUpdates()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
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
        .sheet(isPresented: $showWhoIsWalking) {
            WhoIsWalkingSheet(dogs: dogs,
                              start: { ids in
                                  showWhoIsWalking = false
                                  Task { @MainActor in
                                      try? await Task.sleep(for: .milliseconds(350))
                                      activeWalkCover = .start(ids)
                                  }
                              },
                              cancel: { showWhoIsWalking = false })
        }
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
            journalFilter.includes(isTracked: walk.source != .manual)
                && journalFilter.includes(date: walk.endedAt ?? walk.startedAt,
                                          dogIDs: Set(links.filter { $0.walkID == walk.id }.map(\.dogID)))
        }
        let sharedShown = sharedEntries(own: completed)
        if completed.isEmpty && sharedWalks.isEmpty {
            List {
                LostHouseholdNotice()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                TruffloEmptyStateView(
                    imageName: "EmptyWalk",
                    title: "Aucune balade enregistrée",
                    description: "Les balades de votre journal apparaîtront ici."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                                hero: AnyView(TruffloJournalHero(
                                    title: "Journal",
                                    subtitle: "Tous les souvenirs de vos balades avec \(dogNames).",
                                    photoData: dogs.first(where: { $0.photoData != nil })?.photoData,
                                    onAdd: liveWalk == nil ? { showWalkForm = true } : nil)),
                                chips: AnyView(journalChips))
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

    /// Toutes, Avec GPS, Ajoutées, and the dog and period filter behind the
    /// sliders, as in the mock-up.
    private var journalChips: some View {
        HStack(spacing: TruffloTheme.Spacing.xSmall) {
            TruffloFilterChips(options: JournalFilter.Kind.allCases.map { ($0, $0.label) },
                               selection: $journalFilter.kind)
            Spacer(minLength: 0)
            journalFilterMenu
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                .frame(width: 42, height: 42)
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
                TruffloWelcome { showDogForm = true }
            }
            // The introduction closes onto this screen: same aura, so it continues
            // rather than cuts.
            .background(alignment: .top) {
                TruffloDogAura(photoData: nil)
                    .frame(height: 560)
                    .ignoresSafeArea(edges: .top)
            }
            .safeAreaInset(edge: .bottom) { addDogButton }
        } else {
            let journal = facts
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TruffloTodayHero(name: dogNames,
                                     photoData: dogs.count == 1 ? dogs[0].photoData : nil,
                                     chips: dogs.count == 1 ? heroChips(dogs[0]) : []) {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
                            if dogs.count == 1, dogs[0].photoData == nil {
                                NavigationLink(value: DogRoute(id: dogs[0].id)) {
                                    Label("Ajouter une photo de \(dogs[0].name)", systemImage: "camera")
                                        .font(.truffloBodyHeavy)
                                        .foregroundStyle(Color.truffloForest)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("today.addPhoto")
                            }
                            if let currentWalk = liveWalk {
                                liveWalkSection(currentWalk)
                            } else {
                                startButton
                            }
                        }
                    }

                    if completedWalks.isEmpty {
                        firstWalkPlaceholder
                    } else {
                        todayTiles(journal)
                    }

                    if let line = routineLine(for: dogs[0]) {
                        TruffloWidget(title: "Routine", systemImage: "repeat") {
                            Text(line)
                                .font(.truffloBodyRegular)
                                .foregroundStyle(Color.truffloCharcoal)
                                .accessibilityIdentifier("today.routine")
                        }
                    }

                    if let lastWalk = journal.lastWalkID.flatMap({ id in walks.first { $0.id == id } }) {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
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
                                WalkTile(walk: lastWalk)
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
            .background {
                TruffloTodayBackdrop(name: dogNames, photoData: dogs.count == 1 ? dogs[0].photoData : nil)
            }
            // No blur under the bar: the photo runs clean to the top of the screen.
            .scrollEdgeEffectHidden(true, for: .top)
        }
    }

    /// Breed, age and sex as chips under the name: what the person declared.
    private func heroChips(_ dog: DogRecord) -> [(icon: String?, text: String)] {
        var chips: [(icon: String?, text: String)] = []
        if dog.breedKind != "unknown" { chips.append(("pawprint.fill", dog.breedDescription)) }
        if !dog.ageDescription.isEmpty { chips.append((nil, dog.ageDescription)) }
        if dog.genderDescription != "Non renseigné" { chips.append((nil, dog.genderDescription)) }
        return chips
    }

    /// Three small glass tiles: the week's count, the week's time, and how long
    /// ago the last balade ended. Facts, never a judgement about the dog.
    private func todayTiles(_ journal: JournalFacts) -> some View {
        let week = journal.week
        let last = journal.lastWalkID.flatMap { id in walks.first { $0.id == id } }
        let ago = last.map { ($0.endedAt ?? $0.startedAt).formatted(.relative(presentation: .named, unitsStyle: .abbreviated)
                                .locale(TruffloLocale.french)) } ?? ""
        return HStack(spacing: 10) {
            TruffloStatTile(systemImage: "shoe", tint: Color(red: 0.18, green: 0.42, blue: 0.31),
                            value: "\(week.walkCount)",
                            label: week.walkCount == 1 ? "balade\ncette semaine" : "balades\ncette semaine",
                            iconSize: 19)
            // The middle tile is narrower in the mock-up (105 of 358 pt).
            TruffloStatTile(systemImage: "clock", tint: Color(red: 0.85, green: 0.58, blue: 0.17),
                            value: week.isEmpty ? "0 min" : WalkFormatting.minutes(week.totalSeconds),
                            label: "en tout")
                .frame(width: 105)
            TruffloStatTile(systemImage: "heart.fill", tint: Color(red: 0.23, green: 0.61, blue: 0.44),
                            value: ago.capitalizedFirst,
                            label: "dernière\nbalade",
                            isSentence: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("today.week")
    }

    private var completedWalks: [WalkRecord] { walks.filter { $0.phase == .completed } }

    /// One chien as a widget: its face when there is a photo (no stand-in face
    /// otherwise), its name and declared facts, then its figures in the grid every
    /// card uses. No ranking between chiens.
    private func dogCard(_ dog: DogRecord, walkCount count: Int, totalSeconds: TimeInterval) -> some View {
        let declared = [dog.breedKind != "unknown" ? dog.breedDescription : "", dog.ageDescription,
                        dog.genderDescription == "Non renseigné" ? "" : dog.genderDescription.lowercased()]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            TruffloCardHeader(title: dog.name, subtitle: declared, photo: dog.photoData, photoName: dog.name,
                              titleFont: .system(.title3, design: .rounded, weight: .heavy))
            TruffloStatGrid(items: [
                .init(label: "Balades", value: "\(count)"),
                .init(label: "Temps en tout", value: count == 0 ? "Pas encore" : WalkFormatting.minutes(totalSeconds)),
            ])
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .truffloWidgetSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dog.row.\(dog.id.uuidString)")
    }

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
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
            .accessibilityAddTraits(.isHeader)
    }

    /// The dog at the head of the screen, as a portrait (A2-REQ-05). Without a photo
    /// nothing stands in for it and the header offers the one thing that would change that.
    private var dogHeader: some View {
        let lead = dogs[0]
        return TruffloDogHeader(name: dogNames, photoData: lead.photoData, subtitle: dogSubtitle(lead)) {
            if lead.photoData == nil {
                NavigationLink(value: DogRoute(id: lead.id)) {
                    Label("Ajouter une photo de \(lead.name)", systemImage: "camera")
                        .font(.truffloBodyHeavy)
                        .foregroundStyle(Color.truffloForest)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.addPhoto")
            }
        }
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

    /// The calendar week of this person's own walks (`WeekSummary`, A2-REQ-01):
    /// the figure, the seven days, and the time in one line. Descriptive, never a
    /// target. Distance is not summed, because declared walks have none.
    private var weekFigure: some View {
        let week = facts.week
        let total = week.isEmpty ? nil : "\(WalkFormatting.minutes(week.totalSeconds)) en tout"
        return TruffloWeekFigure(week: week, totalLine: total)
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
            } else if dogs.count > 1 {
                showWhoIsWalking = true
            } else {
                activeWalkCover = .start(dogs.map(\.id))
            }
        }
    }

    /// The one action of the screen, anchored where the thumb rests.
    private var startButton: some View {
        VStack(spacing: TruffloTheme.Spacing.xSmall) {
            Button {
                startTaps += 1
                startWalk()
            } label: {
                HStack(spacing: TruffloTheme.Spacing.small) {
                    Spacer(minLength: 0)
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: "location.fill").font(.headline.weight(.bold))
                    }
                    Text("Partir en balade")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 38)
                .overlay(alignment: .trailing) {
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.15), in: Circle())
                    }
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.truffloForest)
            .sensoryFeedback(.impact(weight: .light), trigger: startTaps)
            Text("Suivi GPS · Même hors ligne")
                .font(.caption)
                .foregroundStyle(Color.truffloSlate)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }

    /// The one action of the welcome screen, anchored like the start button.
    private var addDogButton: some View {
        Button {
            showDogForm = true
        } label: {
            Text("Ajouter mon chien")
                .font(.truffloBodyHeavy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(Color.truffloForest)
        .truffloTap()
        .accessibilityIdentifier("dog.add")
        .padding(.horizontal, TruffloTheme.Spacing.screen)
        .padding(.bottom, TruffloTheme.Spacing.xSmall)
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
