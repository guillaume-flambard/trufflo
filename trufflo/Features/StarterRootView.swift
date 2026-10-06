import SwiftUI
import SwiftData

/// Distinct wrappers so a dog UUID and a walk UUID can never resolve to the
/// wrong detail screen from the same navigation value.
private struct DogRoute: Hashable { let id: UUID }
private struct WalkRoute: Hashable { let id: UUID }

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
                List {
                    if walks.isEmpty {
                        TruffloEmptyStateView(
                            imageName: "EmptyWalk",
                            title: "Aucune balade enregistrée",
                            description: "Les sorties ajoutées à votre journal apparaîtront ici."
                        )
                    }
                    ForEach(walks.filter { $0.phase == .completed }) { walk in
                        NavigationLink(value: WalkRoute(id: walk.id)) { row(for: walk) }
                    }
                }
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dog.name)
                                        .font(.truffloHeadline)
                                        .foregroundStyle(Color.truffloForest)
                                    Text(dog.breedDescription)
                                        .font(.truffloSubheadline)
                                        .foregroundStyle(Color.truffloSlate)
                                }
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
                    if let lastWalk = walks.first(where: { $0.phase == .completed }) {
                        lastWalkSection(lastWalk)
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.large)
                .padding(.vertical, TruffloTheme.Spacing.medium)
            }
        }
    }

    /// Name and breed at the left, the portrait offset to the right. With several
    /// dogs the names are joined and the first dog's portrait stands for them;
    /// the walk itself is started with all of them, as before.
    private var dogHeader: some View {
        let lead = dogs[0]
        return HStack(alignment: .top, spacing: TruffloTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                Text(dogNames)
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .foregroundStyle(Color.truffloForest)
                    .fixedSize(horizontal: false, vertical: true)
                if dogs.count == 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lead.breedDescription)
                        if !lead.ageDescription.isEmpty { Text(lead.ageDescription) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.truffloSlate)
                } else {
                    Text("\(dogs.count) chiens")
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                }
                if let sentence = recentActivitySentence {
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                        .padding(.top, TruffloTheme.Spacing.xSmall)
                }
            }
            Spacer(minLength: 0)
            TruffloDogPortrait(name: lead.name, photoData: lead.photoData, diameter: 120)
                .padding(.top, TruffloTheme.Spacing.xxSmall)
        }
        .accessibilityElement(children: .contain)
    }

    private var dogNames: String {
        dogs.map(\.name).formatted(.list(type: .and).locale(Locale(identifier: "fr_FR")))
    }

    /// "Dernière sortie il y a 18 h" and "3 balades enregistrées cette semaine".
    /// The week is the last seven days, not the calendar week: a calendar week
    /// resets to zero on Monday and reads like a fresh debt. Nothing is shown for
    /// an empty journal rather than a zero.
    private var recentActivitySentence: String? {
        let completed = walks.filter { $0.phase == .completed }
        guard let last = completed.first, let endedAt = last.endedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        var lines = ["Dernière sortie \(formatter.localizedString(for: endedAt, relativeTo: Date()))"]
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let count = completed.filter { ($0.endedAt ?? $0.startedAt) >= weekAgo }.count
        if count > 0 {
            lines.append(count == 1
                         ? "1 balade enregistrée cette semaine"
                         : "\(count) balades enregistrées cette semaine")
        }
        return lines.joined(separator: "\n")
    }

    private func liveWalkSection(_ walk: WalkRecord) -> some View {
        let isInterrupted = walk.phase == .interrupted
        return HStack(alignment: .center, spacing: TruffloTheme.Spacing.medium) {
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
            .buttonStyle(.truffloPrimary)
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walk.live.banner")
    }

    private var startActions: some View {
        VStack(spacing: TruffloTheme.Spacing.small) {
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
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("walk.manual.add")
        }
    }

    /// The last walk as a passage, not a card: a heading, when it happened, the
    /// duration as the figure, and the start of the note. No badge says where it
    /// came from; the detail screen states origin and quality in words.
    private func lastWalkSection(_ walk: WalkRecord) -> some View {
        let names = links.filter { $0.walkID == walk.id }
            .map(\.dogNameSnapshot).sorted().joined(separator: ", ")
        return NavigationLink(value: WalkRoute(id: walk.id)) {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                Text("Dernière balade")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.truffloForest)
                if let endedAt = walk.endedAt {
                    Text(endedAt, format: .dateTime.weekday(.wide).day().month().hour().minute()
                        .locale(Locale(identifier: "fr_FR")))
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(minutes(walk.confirmedSeconds)) min")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.truffloForest)
                    if !names.isEmpty {
                        Text("avec \(names)")
                            .font(.subheadline)
                            .foregroundStyle(Color.truffloSlate)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.truffloSlate)
                        .accessibilityHidden(true)
                }
                if !walk.note.isEmpty {
                    Text(walk.note)
                        .font(.body)
                        .foregroundStyle(Color.truffloCharcoal)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, TruffloTheme.Spacing.medium)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.truffloForest.opacity(0.12)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("walk.row.\(walk.id.uuidString)")
    }

    private func row(for walk: WalkRecord) -> some View {
        let names = links.filter { $0.walkID == walk.id }
            .map(\.dogNameSnapshot).sorted().joined(separator: ", ")
        return VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
            HStack {
                Text(names.isEmpty ? "Balade" : names)
                    .font(.truffloHeadline)
                    .foregroundStyle(Color.truffloForest)
                Spacer()
                TruffloBadge("\(minutes(walk.confirmedSeconds)) min", icon: "timer", style: .sage)
            }
            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                TruffloBadge(walk.source == .manual ? "Saisie manuelle" : "Suivi GPS",
                             icon: walk.source == .manual ? "square.and.pencil" : "location.fill",
                             style: walk.source == .manual ? .sand : .peach)
                if let endedAt = walk.endedAt {
                    Text(endedAt, format: .dateTime.day().month().hour().minute())
                        .font(.truffloCaption)
                        .foregroundStyle(Color.truffloSlate)
                }
            }
            if !walk.note.isEmpty {
                Text(walk.note)
                    .font(.truffloBody)
                    .foregroundStyle(Color.truffloCharcoal)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("walk.row.\(walk.id.uuidString)")
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        (seconds / 60).formatted(.number.precision(.fractionLength(0...1)))
    }

    private func eraseAll() {
        do { try JournalRepository(context: context).eraseAll() }
        catch { storageError = true }
    }
}
