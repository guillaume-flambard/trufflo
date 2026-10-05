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
                List {
                    Section {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                            Text("À son rythme. Ensemble.")
                                .font(.truffloTitle)
                                .foregroundStyle(Color.truffloForest)
                            Text("Retrouvez les balades que vous avez enregistrées.")
                                .font(.truffloSubheadline)
                                .foregroundStyle(Color.truffloCharcoal.opacity(0.7))
                        }
                        .padding(.vertical, TruffloTheme.Spacing.xSmall)
                    }

                    if let currentWalk = liveWalk {
                        let isInterrupted = currentWalk.phase == .interrupted
                        Section(isInterrupted ? "Balade interrompue" : "Balade en cours") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(isInterrupted ? "Session interrompue" : "Suivi GPS actif")
                                        .font(.truffloHeadline)
                                        .foregroundStyle(Color.truffloForest)
                                    Text(currentWalk.phase == .recording
                                         ? "En cours d'enregistrement..."
                                         : isInterrupted ? "Données enregistrées jusqu'au dernier point."
                                         : "En pause")
                                        .font(.truffloCaption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Afficher") {
                                    activeWalkCover = .resume(currentWalk.id)
                                }
                                .buttonStyle(.truffloPrimary)
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("walk.live.banner")
                        }
                    }

                    if dogs.isEmpty {
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
                    } else {
                        Section("Démarrer une balade") {
                            Button {
                                if let dog = dogs.first {
                                    activeWalkCover = .start
                                }
                            } label: {
                                Label("Démarrer une balade GPS", systemImage: "location.circle.fill")
                                    .font(.truffloHeadline)
                                    .foregroundStyle(Color.truffloForest)
                            }

                            Button {
                                showWalkForm = true
                            } label: {
                                Label("Ajouter une balade passée", systemImage: "plus.circle.fill")
                                    .font(.truffloSubheadline)
                                    .foregroundStyle(Color.truffloForest.opacity(0.8))
                            }
                            .accessibilityIdentifier("walk.manual.add")
                        }
                        if let lastWalk = walks.first(where: { $0.phase == .completed }) {
                            Section("Dernière balade enregistrée") {
                                NavigationLink(value: WalkRoute(id: lastWalk.id)) {
                                    row(for: lastWalk)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Aujourd'hui")
                .tint(Color.truffloForest)
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
                .tint(Color.truffloForest)
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
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("dog.row.\(dog.id.uuidString)")
                            }
                        }
                    }
                }
                .navigationTitle("Mes chiens")
                .tint(Color.truffloForest)
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
                        .foregroundStyle(.secondary)
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
