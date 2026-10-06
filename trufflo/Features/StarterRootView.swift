import SwiftUI
import SwiftData

/// Distinct wrappers so a dog UUID and a walk UUID can never resolve to the
/// wrong detail screen from the same navigation value.
private struct DogRoute: Hashable { let id: UUID }
struct WalkRoute: Hashable { let id: UUID }

private enum ActiveWalkCover: Identifiable {
    case resume(UUID)
    case start

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
                            NavigationLink(value: DogRoute(id: dog.id)) {
                                HStack(spacing: TruffloTheme.Spacing.medium) {
                                    TruffloDogPortrait(name: dog.name, photoData: dog.photoData, diameter: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dog.name)
                                            .font(.system(.title3, design: .rounded, weight: .bold))
                                            .foregroundStyle(Color.truffloForest)
                                        Text(walkCountText(for: dog))
                                            .font(.subheadline)
                                            .foregroundStyle(Color.truffloSlate)
                                    }
                                }
                                .padding(.vertical, TruffloTheme.Spacing.xxSmall)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("dog.row.\(dog.id.uuidString)")
                            }
                        }
                    }
                }
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
        .fullScreenCover(item: $activeWalkCover) { cover in
            switch cover {
            case .resume(let walkID):
                ActiveWalkView(modelContainer: context.container, existingWalkID: walkID)
            case .start:
                ActiveWalkView(modelContainer: context.container, dogIDs: dogs.map(\.id))
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
        if completed.isEmpty {
            List {
                TruffloEmptyStateView(
                    imageName: "EmptyWalk",
                    title: "Aucune balade enregistrée",
                    description: "Les sorties ajoutées à votre journal apparaîtront ici."
                )
            }
        } else {
            JournalTimelineView(walks: completed, rowDestination: { WalkRoute(id: $0) })
        }
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
                    if let currentWalk = liveWalk { liveWalkSection(currentWalk) }
                    startActions
                    weekSection
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
                    TruffloStat("Temps", value: WalkFormatting.minutes(week.map(\.confirmedSeconds).reduce(0, +)))
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

    private func liveWalkSection(_ walk: WalkRecord) -> some View {
        let isInterrupted = walk.phase == .interrupted
        return HStack(alignment: .center, spacing: TruffloTheme.Spacing.medium) {
            Circle()
                .fill(isInterrupted ? Color.truffloPeach : Color.truffloSage)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(isInterrupted ? "Session interrompue" : "Suivi GPS actif")
                    .font(.headline)
                    .foregroundStyle(Color.truffloForest)
                Text(walk.phase == .recording
                     ? "En cours d'enregistrement..."
                     : isInterrupted ? "Données enregistrées jusqu'au dernier point."
                     : "En pause")
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
            }
            Spacer(minLength: 0)
            Button("Afficher") {
                activeWalkCover = .resume(walk.id)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.truffloForest)
            .fixedSize()
        }
        .padding(TruffloTheme.Spacing.medium)
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walk.live.banner")
    }

    private var startActions: some View {
        VStack(spacing: TruffloTheme.Spacing.xSmall) {
            Button {
                // An unfinished walk, interrupted included, is not a reason to
                // open a second session: the repository would hand the existing
                // one back and the tap would look like it did nothing. Open that
                // one instead.
                if let unfinished = liveWalk {
                    activeWalkCover = .resume(unfinished.id)
                } else if dogs.first != nil {
                    activeWalkCover = .start
                }
            } label: {
                Label("Démarrer une balade GPS", systemImage: "location.fill")
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

    private func eraseAll() {
        do { try JournalRepository(context: context).eraseAll() }
        catch { storageError = true }
    }
}
