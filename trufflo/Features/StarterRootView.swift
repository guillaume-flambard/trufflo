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
    @State private var showDogForm = false
    @State private var showWalkForm = false
    @State private var activeWalkCover: ActiveWalkCover?
    @State private var showEraseConfirmation = false
    @State private var storageError = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboardingSheet = false
    @State private var startBlock: LocationBlock?
    @State private var exportFile: SharedFile?
    @State private var showWhoIsWalking = false
    @State private var journalFilter = JournalFilter()
    @State private var exportError: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var liveWalk: WalkRecord? {
        walks.first { $0.phase == .recording || $0.phase == .paused || $0.phase == .interrupted }
    }

    var body: some View {
        TabView {
            NavigationStack {
                todayContent
                .navigationTitle("Aujourd'hui")
                .navigationBarTitleDisplayMode(.inline)
                .truffloScreen()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Réglages", systemImage: "gearshape") {
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
                .navigationDestination(for: WalkRoute.self) { WalkDetailView(walkID: $0.id) }
                .navigationDestination(for: DogRoute.self) { DogDetailView(dogID: $0.id) }
            }
            .tabItem { Label("Aujourd'hui", systemImage: "sun.max") }

            NavigationStack {
                journalContent
                .navigationTitle("Journal")
                .truffloScreen()
                .toolbar {
                    if walks.contains(where: { $0.phase == .completed }) {
                        ToolbarItem(placement: .topBarTrailing) { journalFilterMenu }
                    }
                }
                .navigationDestination(for: WalkRoute.self) { WalkDetailView(walkID: $0.id) }
                .navigationDestination(for: DogRoute.self) { DogDetailView(dogID: $0.id) }
            }
            .tabItem { Label("Journal", systemImage: "book") }

            NavigationStack {
                List {
                    if dogs.isEmpty {
                        TruffloEmptyStateView(
                            imageName: "EmptyDog",
                            title: "Aucun profil créé",
                            description: "Ajoutez un profil pour personnaliser le journal de votre compagnon.",
                            buttonTitle: "Ajouter un chien",
                            action: { showDogForm = true }
                        )
                    } else {
                        ForEach(dogs) { dog in
                            // The link sits behind the card so the list draws no
                            // disclosure chevron outside it.
                            dogCard(dog)
                                .background(NavigationLink(value: DogRoute(id: dog.id)) { EmptyView() }.opacity(0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Mes chiens")
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
            .tabItem { Label("Mes chiens", systemImage: "pawprint") }
        }
        .tint(Color.truffloForest)
        .sheet(isPresented: $showDogForm) { DogFormView() }
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
        .fullScreenCover(isPresented: $showOnboardingSheet) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboardingSheet = false
            }
        }
        .onAppear {
            if !isUITesting && !hasCompletedOnboarding {
                showOnboardingSheet = true
            }
        }
        .confirmationDialog("Effacer le journal et les profils de cet appareil ?",
                            isPresented: $showEraseConfirmation, titleVisibility: .visible) {
            Button("Tout effacer", role: .destructive, action: eraseAll)
        } message: {
            Text("Cette suppression locale ne peut pas être annulée dans le starter.")
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
            journalFilter.includes(date: walk.endedAt ?? walk.startedAt,
                                   dogIDs: Set(links.filter { $0.walkID == walk.id }.map(\.dogID)))
        }
        if completed.isEmpty {
            List {
                TruffloEmptyStateView(
                    imageName: "EmptyWalk",
                    title: "Aucune balade enregistrée",
                    description: "Les sorties ajoutées à votre journal apparaîtront ici."
                )
            }
        } else if shown.isEmpty {
            TruffloNotice(title: "Aucune balade pour ce filtre",
                          message: "Aucune sortie enregistrée ne correspond au chien et à la période choisis.",
                          actionTitle: "Tout afficher") { journalFilter = JournalFilter() }
        } else {
            JournalTimelineView(walks: shown,
                                filterSummary: journalFilter.isActive ? filterSummary(count: shown.count) : nil,
                                rowDestination: { WalkRoute(id: $0) })
        }
    }

    /// "3 balades, Oslo, 30 derniers jours": says what the filtered list is.
    private func filterSummary(count: Int) -> String {
        var parts = [count == 1 ? "1 balade" : "\(count) balades"]
        if let id = journalFilter.dogID, let dog = dogs.first(where: { $0.id == id }) { parts.append(dog.name) }
        if journalFilter.period != .all { parts.append(journalFilter.period.label.lowercased()) }
        return parts.joined(separator: ", ")
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
            Label("Filtrer", systemImage: journalFilter.isActive
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("journal.filter")
    }

    // MARK: - Today

    /// Today is not a list. The dog is the subject, the start button is the one
    /// action, and the last walk is read as a short passage rather than a card.
    /// Facts here are descriptive (a count, an age of the last outing) and never a
    /// target, a streak or a comparison.
    @ViewBuilder
    private var todayContent: some View {
        if dogs.isEmpty {
            List {
                Section {
                    TruffloEmptyStateView(
                        imageName: "EmptyDog",
                        title: "Bienvenue dans Trufflo",
                        description: "Ajoutez votre chien pour commencer votre journal de balades.",
                        buttonTitle: "Ajouter mon chien",
                        action: { showDogForm = true }
                    )
                    .accessibilityIdentifier("dog.add")
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    dogHeader
                    if let currentWalk = liveWalk {
                        liveWalkSection(currentWalk)
                    } else {
                        startActions
                    }
                    weekSection
                    if completedWalks.isEmpty {
                        firstWalkPlaceholder
                    }
                    if let lastWalk = completedWalks.first {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                            sectionTitle("Dernière balade")
                            NavigationLink(value: WalkRoute(id: lastWalk.id)) {
                                WalkActivityCard(walk: lastWalk)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.medium)
                .padding(.vertical, TruffloTheme.Spacing.medium)
            }
        }
    }

    private var completedWalks: [WalkRecord] { walks.filter { $0.phase == .completed } }

    /// A dog is a real object, so it is a card: face, name, declared facts, and
    /// the number of walks shared with it. No ranking between dogs.
    private func dogCard(_ dog: DogRecord) -> some View {
        let facts = [dog.breedKind != "unknown" ? dog.breedDescription : "", dog.ageDescription]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        let count = walkCount(for: dog)
        return HStack(spacing: TruffloTheme.Spacing.medium) {
            TruffloDogPortrait(name: dog.name, photoData: dog.photoData, diameter: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(dog.name)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(Color.truffloForest)
                if !facts.isEmpty {
                    Text(facts).font(.subheadline).foregroundStyle(Color.truffloSlate)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(count)").font(.truffloFigure(.title2)).monospacedDigit().foregroundStyle(Color.truffloForest)
                Text(count == 1 ? "balade" : "balades").font(.footnote).foregroundStyle(Color.truffloSlate)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
            .strokeBorder(Color.truffloForest.opacity(0.07), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dog.row.\(dog.id.uuidString)")
    }

    private func walkCount(for dog: DogRecord) -> Int {
        let finished = Set(completedWalks.map(\.id))
        return links.filter { $0.dogID == dog.id && finished.contains($0.walkID) }.count
    }

    private func walkCountText(for dog: DogRecord) -> String {
        let finished = Set(completedWalks.map(\.id))
        let count = links.filter { $0.dogID == dog.id && finished.contains($0.walkID) }.count
        switch count {
        case 0: return "Pas encore de balade"
        case 1: return "1 balade enregistrée"
        default: return "\(count) balades enregistrées"
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(Color.truffloForest)
            .accessibilityAddTraits(.isHeader)
    }

    /// The dog leads. Side by side at normal sizes; at accessibility sizes the
    /// portrait goes above the name so neither is squeezed.
    @ViewBuilder
    private var dogHeader: some View {
        let lead = dogs[0]
        let identity = VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
            Text(dogNames)
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.truffloForest)
                .fixedSize(horizontal: false, vertical: true)
            Text(dogSubtitle(lead))
                .font(.subheadline)
                .foregroundStyle(Color.truffloSlate)
        }
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                TruffloDogPortrait(name: lead.name, photoData: lead.photoData, diameter: 88)
                identity
            }
        } else {
            HStack(alignment: .center, spacing: TruffloTheme.Spacing.medium) {
                identity
                Spacer(minLength: 0)
                TruffloDogPortrait(name: lead.name, photoData: lead.photoData, diameter: 104)
            }
        }
    }

    private func dogSubtitle(_ lead: DogRecord) -> String {
        guard dogs.count == 1 else { return "\(dogs.count) chiens" }
        let parts = [lead.breedKind != "unknown" ? lead.breedDescription : "", lead.ageDescription]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Prêt pour la balade" : parts.joined(separator: ", ")
    }

    private var dogNames: String {
        dogs.map(\.name).formatted(.list(type: .and).locale(Locale(identifier: "fr_FR")))
    }

    /// Descriptive figures over the last seven days, never a target: how many
    /// walks, how much time recorded, how long since the last outing. Distance
    /// is not summed, because declared walks have none. Hidden when the week is
    /// empty rather than showing zeros.
    @ViewBuilder
    private var weekSection: some View {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let week = completedWalks.filter { ($0.endedAt ?? $0.startedAt) >= weekAgo }
        if !week.isEmpty {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("Cette semaine")
                    if let ago = lastOutingAgo {
                        Text("Dernière sortie \(ago)")
                            .font(.subheadline)
                            .foregroundStyle(Color.truffloSlate)
                    }
                }
                TruffloStatRow {
                    TruffloStat("Balades", value: "\(week.count)")
                    TruffloStat("Temps enregistré", value: WalkFormatting.minutes(week.map(\.confirmedSeconds).reduce(0, +)))
                }
            }
        }
    }

    private var lastOutingAgo: String? {
        guard let endedAt = completedWalks.first?.endedAt else { return nil }
        if Date().timeIntervalSince(endedAt) < 60 { return "à l'instant" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: endedAt, relativeTo: Date())
    }

    /// A walk in progress takes the place of the start button, so a second one
    /// cannot be started by mistake. The time keeps running on screen: the
    /// stored duration covers the last checkpoint, and while recording the
    /// seconds since that checkpoint are added on top.
    private func liveWalkSection(_ walk: WalkRecord) -> some View {
        let isInterrupted = walk.phase == .interrupted
        let isRecording = walk.phase == .recording
        return VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                Circle()
                    .fill(isInterrupted ? Color.truffloPeach : isRecording ? Color(red: 0.5, green: 0.83, blue: 0.65) : Color.white.opacity(0.7))
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Text(isInterrupted ? "Balade interrompue" : isRecording ? "Balade en cours" : "Balade en pause")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.truffloMint)
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
                    .font(.footnote)
                    .foregroundStyle(Color.truffloMint)
            }
            Button {
                activeWalkCover = .resume(walk.id)
            } label: {
                Text("Revenir à la balade")
                    .font(.headline)
                    .foregroundStyle(Color.truffloForest)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.truffloForest, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walk.live.banner")
    }

    private func liveFigure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(Color.truffloMint)
            Text(value)
                .font(.truffloFigure(.title))
                .monospacedDigit()
                .foregroundStyle(.white)
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

    private var startActions: some View {
        VStack(spacing: TruffloTheme.Spacing.xSmall) {
            Button(action: startWalk) {
                Label("Démarrer une balade", systemImage: "location.fill")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: TruffloTheme.Radius.medium))
            .tint(Color.truffloForest)

            Button {
                showWalkForm = true
            } label: {
                Text("Ajouter une balade passée")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.truffloForest)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("walk.manual.add")
        }
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
        do { try JournalRepository(context: context).eraseAll() }
        catch { storageError = true }
    }
}

extension LocationBlock: Identifiable {
    public var id: String { rawValue }
}
