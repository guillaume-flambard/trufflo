import SwiftUI
import SwiftData

@MainActor
struct StarterRootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]
    @Query(sort: \WalkRecord.startedAt, order: .reverse) private var walks: [WalkRecord]
    @Query private var links: [WalkDogRecord]
    @State private var showDogForm = false
    @State private var showWalkForm = false
    @State private var showEraseConfirmation = false
    @State private var storageError = false

    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section {
                        Text("À son rythme. Ensemble.")
                            .font(.title2.weight(.semibold))
                        Text("Retrouvez les balades que vous avez enregistrées.")
                            .foregroundStyle(.secondary)
                    }
                    if dogs.isEmpty {
                        Section {
                            ContentUnavailableView(
                                "Bienvenue dans Trufflo",
                                systemImage: "pawprint",
                                description: Text("Ajoutez votre chien pour commencer votre journal.")
                            )
                            Button("Ajouter mon chien") { showDogForm = true }
                                .accessibilityIdentifier("dog.add")
                        }
                    } else {
                        Section("Votre journal") {
                            Button("Ajouter une balade passée", systemImage: "plus.circle") {
                                showWalkForm = true
                            }
                            .accessibilityIdentifier("walk.manual.add")
                            Text("Ce starter permet la saisie manuelle. Le suivi GPS n'est pas encore branché.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let lastWalk = walks.first {
                            Section("Dernière balade enregistrée") { row(for: lastWalk) }
                        }
                    }
                }
                .navigationTitle("Aujourd'hui")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Réglages", systemImage: "gearshape") {
                            Button("Effacer toutes les données", role: .destructive) {
                                showEraseConfirmation = true
                            }
                        }
                    }
                }
            }
            .tabItem { Label("Aujourd'hui", systemImage: "sun.max") }

            NavigationStack {
                List {
                    if walks.isEmpty {
                        ContentUnavailableView(
                            "Aucune balade enregistrée",
                            systemImage: "book.closed",
                            description: Text("Les sorties ajoutées à votre journal apparaîtront ici.")
                        )
                    }
                    ForEach(walks) { walk in row(for: walk) }
                }
                .navigationTitle("Journal")
            }
            .tabItem { Label("Journal", systemImage: "book") }

            NavigationStack {
                List(dogs) { dog in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dog.name).font(.headline)
                        Text(breedDescription(dog)).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Mes chiens")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Ajouter", systemImage: "plus") { showDogForm = true }
                            .accessibilityIdentifier("dog.add.secondary")
                    }
                }
            }
            .tabItem { Label("Mes chiens", systemImage: "pawprint") }
        }
        .sheet(isPresented: $showDogForm) { DogFormView() }
        .sheet(isPresented: $showWalkForm) { ManualWalkFormView(dogs: dogs) }
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
        let minutes = (walk.confirmedSeconds / 60).formatted(.number.precision(.fractionLength(0...1)))
        return VStack(alignment: .leading, spacing: 6) {
            Text(names.isEmpty ? "Balade" : names).font(.headline)
            Text("\(minutes) min · \(walk.source == .manual ? "Saisie manuelle" : "Suivi GPS")")
            if let endedAt = walk.endedAt {
                Text(endedAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !walk.note.isEmpty { Text(walk.note).font(.subheadline) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("walk.row.\(walk.id.uuidString)")
    }

    private func breedDescription(_ dog: DogRecord) -> String {
        switch dog.breedKind {
        case "known": dog.breedLabel
        case "mixed": "Croisé"
        default: "Race inconnue"
        }
    }

    private func eraseAll() {
        for link in links { context.delete(link) }
        for walk in walks { context.delete(walk) }
        for dog in dogs { context.delete(dog) }
        do { try context.save() }
        catch { context.rollback(); storageError = true }
    }
}