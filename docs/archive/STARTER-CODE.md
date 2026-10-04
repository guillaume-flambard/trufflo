> **Archive, non maintenu.** Copie du code livré dans le pack natif du
> 4 octobre 2026, extraite de `TRUFFLO-NATIVE-STARTER-ALL.md`. Les sources qui
> tournent réellement sont dans `trufflo/` et ont divergé depuis. En cas de
> divergence, le code l'emporte.

---

# Starter Swift — fichiers à extraire du Markdown

**Portée : M0 + noyau de M1.** Ces fichiers fournissent un journal manuel local et un moteur de transitions/segmentation. Ils ne livrent pas l’adaptateur Core Location, la carte, l’acteur de tracés, les objectifs, le cloud ou la communauté.

Les 22 tests du domaine ont été exécutés avec Swift 6.2.1 sous Linux. Les autres fichiers ont passé une analyse syntaxique Swift, mais **leur compilation avec SwiftUI/SwiftData et les tests natifs restent à effectuer dans Xcode**. Voir VERIFICATION.md. Ne pas annoncer une application prête pour TestFlight sur la base de ces extraits.

## Mode d’emploi

Conserver Product Name/module `trufflo`, nom affiché Trufflo. Configurer Swift 6 et une isolation par défaut Nonisolated, avec les frontières MainActor explicites fournies. Placer les blocs dans les fichiers indiqués et sélectionner leur bonne cible. Remplacer le point d’entrée généré et retirer les références aux exemples `Item`/`ContentView` qui ne servent plus. Ne jamais compiler deux fois le même fichier ni effacer une base réelle pour adapter le schéma.

Les identifiants des tests supposent l’interface française fournie. Le catalogue FR/EN est une tâche suivante. Les textes indiquant les limites M0 sont intentionnels, à remplacer seulement quand les comportements M1 existent.


## `trufflo/Domain/WalkDomain.swift`

Cible app. Valeurs et règles sans dépendance iOS ; noyau testé.

```swift
import Foundation

public enum WalkPhase: String, Codable, Sendable {
    case recording, paused, interrupted, completed, discarded
}

public enum WalkError: Error, Equatable, Sendable {
    case invalidTransition
    case invalidDuration
    case missingDog
    case noteTooLong
}

/// Persist this snapshot after every accepted state change.
/// The coordinator supplies monotonic elapsed time only while its live session exists.
/// Never derive an elapsed delta from a persisted wall-clock date after a cold launch.
public struct WalkProgress: Codable, Equatable, Sendable {
    public private(set) var phase: WalkPhase = .recording
    public private(set) var confirmedSeconds: TimeInterval = 0

    public init() {}

    public mutating func accrue(seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds >= 0,
              (confirmedSeconds + seconds).isFinite else {
            throw WalkError.invalidDuration
        }
        guard phase == .recording else { throw WalkError.invalidTransition }
        confirmedSeconds += seconds
    }

    public mutating func pause() throws {
        if phase == .paused { return }
        guard phase == .recording else { throw WalkError.invalidTransition }
        phase = .paused
    }

    public mutating func resume() throws {
        if phase == .recording { return }
        guard phase == .paused || phase == .interrupted else {
            throw WalkError.invalidTransition
        }
        phase = .recording
    }

    public mutating func finish() throws {
        if phase == .completed { return }
        guard phase != .discarded else { throw WalkError.invalidTransition }
        phase = .completed
    }

    public mutating func discard() throws {
        if phase == .discarded { return }
        guard phase != .completed else { throw WalkError.invalidTransition }
        phase = .discarded
    }

    /// Cold-launch recovery never adds time since the last persisted checkpoint.
    public mutating func recoverAfterColdLaunch() {
        if phase == .recording || phase == .paused { phase = .interrupted }
    }
}

public struct ManualWalkInput: Equatable, Sendable {
    public let dogIDs: [UUID]
    public let durationSeconds: TimeInterval
    public let note: String

    public init(dogIDs: [UUID], durationSeconds: TimeInterval, note: String = "") throws {
        guard !dogIDs.isEmpty else { throw WalkError.missingDog }
        // This is an input sanity limit, not an exercise recommendation.
        guard durationSeconds.isFinite, durationSeconds > 0,
              durationSeconds <= 86_400 else { throw WalkError.invalidDuration }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanNote.count <= 500 else { throw WalkError.noteTooLong }
        self.dogIDs = Array(Set(dogIDs)).sorted { $0.uuidString < $1.uuidString }
        self.durationSeconds = durationSeconds
        self.note = cleanNote
    }
}

public struct LocationFix: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

public enum FixOutcome: Equatable, Sendable {
    case anchor(segment: Int)
    case accepted(segment: Int, addedMeters: Double)
    case ignoredDuplicateOrOld
    case rejected
}

/// Initial filter for experiments, not a claim of measured GPS accuracy.
/// Store the outcome/segment alongside accepted coordinates; never join segments in a map.
public struct TrackAccumulator: Sendable {
    public private(set) var distanceMeters: Double = 0
    public private(set) var isPartial = false
    public private(set) var measuredEdgeCount = 0
    public private(set) var segment = 0
    private var anchor: LocationFix?
    private var latestTimestamp: Date?

    // Technical hypothesis values to calibrate in field tests, never dog-health rules.
    public let maximumAccuracy: Double = 35
    public let maximumGap: TimeInterval = 45
    public let maximumSpeed: Double = 12

    public init() {}

    public var measuredDistance: Double? {
        measuredEdgeCount > 0 ? distanceMeters : nil
    }

    /// A manual pause is a deliberate break, not necessarily lost GPS data.
    public mutating func breakSegment(markPartial: Bool = false) {
        anchor = nil
        if markPartial { isPartial = true }
    }

    public mutating func ingest(_ fix: LocationFix) -> FixOutcome {
        guard fix.latitude.isFinite, fix.longitude.isFinite,
              (-90...90).contains(fix.latitude), (-180...180).contains(fix.longitude),
              fix.horizontalAccuracy.isFinite, fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= maximumAccuracy,
              fix.timestamp.timeIntervalSince1970.isFinite else {
            breakSegment(markPartial: true)
            return .rejected
        }
        if let latestTimestamp, fix.timestamp <= latestTimestamp {
            return .ignoredDuplicateOrOld
        }
        latestTimestamp = fix.timestamp
        guard let previous = anchor else {
            segment += 1
            anchor = fix
            return .anchor(segment: segment)
        }
        let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
        if seconds > maximumGap {
            isPartial = true
            segment += 1
            anchor = fix
            return .anchor(segment: segment)
        }
        let meters = Self.distance(from: previous, to: fix)
        guard meters.isFinite, seconds > 0, meters / seconds <= maximumSpeed else {
            breakSegment(markPartial: true)
            return .rejected
        }
        // No jitter suppression is claimed here; calibrate it before release.
        distanceMeters += meters
        measuredEdgeCount += 1
        anchor = fix
        return .accepted(segment: segment, addedMeters: meters)
    }

    private static func distance(from a: LocationFix, to b: LocationFix) -> Double {
        let radians = Double.pi / 180
        let lat1 = a.latitude * radians
        let lat2 = b.latitude * radians
        let dLat = (b.latitude - a.latitude) * radians
        let dLon = (b.longitude - a.longitude) * radians
        let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2)
        let clamped = min(1, max(0, h))
        return 6_371_008.8 * 2 * atan2(sqrt(clamped), sqrt(1 - clamped))
    }
}
```

## `trufflo/Data/Models.swift`

Cible app. Schéma local expérimental M0 ; aucune migration de données existantes implicite.

```swift
import Foundation
import SwiftData

@Model
final class DogRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var breedKind: String
    var breedLabel: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, breedKind: String, breedLabel: String = "") {
        self.id = id
        self.name = name
        self.breedKind = breedKind
        self.breedLabel = breedLabel
        self.createdAt = .now
    }
}

@Model
final class WalkRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Double
    var source: String
    var note: String

    init(id: UUID = UUID(), endedAt: Date, durationSeconds: Double, note: String) {
        self.id = id
        self.startedAt = endedAt.addingTimeInterval(-durationSeconds)
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.source = "manual"
        self.note = note
    }
}

// Explicit links: the repository, not SwiftData, must maintain referential integrity.
// The first starter supports global erasure; individual deletion is a later tested command.
@Model
final class WalkDogRecord {
    @Attribute(.unique) var id: UUID
    var walkID: UUID
    var dogID: UUID
    var dogNameSnapshot: String

    init(walkID: UUID, dogID: UUID, dogNameSnapshot: String) {
        self.id = UUID()
        self.walkID = walkID
        self.dogID = dogID
        self.dogNameSnapshot = dogNameSnapshot
    }
}
```

## `trufflo/Data/PersistenceFactory.swift`

Cible app. Un conteneur local, CloudKit explicitement désactivé.

```swift
import SwiftData

@MainActor
enum PersistenceFactory {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([DogRecord.self, WalkRecord.self, WalkDogRecord.self])
        let configuration = ModelConfiguration(
            "TruffloLocal",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

## `trufflo/truffloApp.swift`

Remplacer le point d’entrée généré, ne pas ajouter un deuxième @main.

```swift
import Foundation
import SwiftUI
import SwiftData

@main
@MainActor
struct TruffloApp: App {
    private let boot: Result<ModelContainer, Error>

    init() {
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("--uitesting")
        #else
        let inMemory = false
        #endif
        boot = Result { try PersistenceFactory.make(inMemory: inMemory) }
    }

    var body: some Scene {
        WindowGroup {
            switch boot {
            case .success(let container):
                StarterRootView()
                    .modelContainer(container)
            case .failure:
                // Never replace a failed persistent store with a silent, empty memory store.
                ContentUnavailableView(
                    "Journal indisponible",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Le stockage n’a pas pu être ouvert. Vos données ne sont pas effacées. Fermez puis rouvrez l’application ; si le problème persiste, conservez l’installation pour le diagnostic.")
                )
            }
        }
    }
}
```

## `trufflo/Features/StarterRootView.swift`

Cible app. Journal manuel, trois tabs et effacement global ; aucune simulation GPS.

```swift
import SwiftUI
import SwiftData

@MainActor
struct StarterRootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]
    @Query(sort: \WalkRecord.endedAt, order: .reverse) private var walks: [WalkRecord]
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
                            Text("Ce starter permet la saisie manuelle. Le suivi GPS n’est pas encore branché.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let lastWalk = walks.first {
                            Section("Dernière balade enregistrée") { row(for: lastWalk) }
                        }
                    }
                }
                .navigationTitle("Aujourd’hui")
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
            .tabItem { Label("Aujourd’hui", systemImage: "sun.max") }

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
            Text("La modification n’a pas été enregistrée. Les données précédentes ont été conservées.")
        }
    }

    private func row(for walk: WalkRecord) -> some View {
        let names = links.filter { $0.walkID == walk.id }
            .map(\.dogNameSnapshot).sorted().joined(separator: ", ")
        let minutes = (walk.durationSeconds / 60).formatted(.number.precision(.fractionLength(0...1)))
        return VStack(alignment: .leading, spacing: 6) {
            Text(names.isEmpty ? "Balade" : names).font(.headline)
            Text("\(minutes) min · Saisie manuelle")
            Text(walk.endedAt, format: .dateTime.day().month().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
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
```

## `trufflo/Features/Dogs/DogFormView.swift`

Cible app. Nom et race ; âge/photo sont des tickets M1.

```swift
import Foundation
import SwiftUI
import SwiftData

@MainActor
struct DogFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var breedKind = "unknown"
    @State private var breedLabel = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Votre chien") {
                    TextField("Nom", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("dog.name")
                    Picker("Race", selection: $breedKind) {
                        Text("Race inconnue").tag("unknown")
                        Text("Croisé").tag("mixed")
                        Text("Race connue").tag("known")
                    }
                    if breedKind == "known" { TextField("Nom de la race", text: $breedLabel) }
                }
                Section {
                    Text("La race ne déclenche pas d’objectif automatique. L’âge et la photo seront ajoutés dans le prochain jalon.")
                        .font(.footnote)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Ajouter un chien")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .accessibilityIdentifier("dog.save")
                }
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBreed = breedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 80 else {
            errorMessage = "Saisissez un nom de 1 à 80 caractères."
            return
        }
        guard breedKind != "known" || (!cleanBreed.isEmpty && cleanBreed.count <= 100) else {
            errorMessage = "Renseignez la race ou sélectionnez « Race inconnue »."
            return
        }
        let dog = DogRecord(name: cleanName, breedKind: breedKind,
                            breedLabel: breedKind == "known" ? cleanBreed : "")
        context.insert(dog)
        do { try context.save(); dismiss() }
        catch {
            context.rollback()
            errorMessage = "Le profil n’a pas été enregistré. Réessayez sans fermer ce formulaire."
        }
    }
}
```

## `trufflo/Features/Walk/ManualWalkFormView.swift`

Cible app. Saisie déclarative avec plusieurs chiens et écriture cohérente.

```swift
import Foundation
import SwiftUI
import SwiftData

@MainActor
struct ManualWalkFormView: View {
    let dogs: [DogRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDogs: Set<UUID> = []
    @State private var minutesText = ""
    @State private var endedAt = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Chiens présents") {
                    ForEach(dogs) { dog in
                        Toggle(dog.name, isOn: Binding(
                            get: { selectedDogs.contains(dog.id) },
                            set: { selected in
                                if selected { selectedDogs.insert(dog.id) }
                                else { selectedDogs.remove(dog.id) }
                            }
                        ))
                    }
                }
                Section("Balade passée") {
                    DatePicker("Fin de la balade", selection: $endedAt,
                               in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    TextField("Durée en minutes", text: $minutesText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("walk.minutes")
                    TextField("Note facultative", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                    Text("Durée déclarée. Aucune distance ni aucun pas ne sont inventés.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Ajouter une balade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .accessibilityIdentifier("walk.save")
                }
            }
        }
        .onAppear {
            if selectedDogs.isEmpty, let first = dogs.first { selectedDogs.insert(first.id) }
        }
    }

    private func save() {
        let normalized = minutesText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let minutes = Double(normalized), endedAt <= Date() else {
            errorMessage = "Saisissez une durée valide et une date de fin passée."
            return
        }
        do {
            let input = try ManualWalkInput(dogIDs: Array(selectedDogs),
                                            durationSeconds: minutes * 60, note: note)
            let selectedProfiles = dogs.filter { input.dogIDs.contains($0.id) }
            guard selectedProfiles.count == input.dogIDs.count else {
                errorMessage = "Un profil a changé. Rouvrez ce formulaire."
                return
            }
            let walk = WalkRecord(endedAt: endedAt, durationSeconds: input.durationSeconds,
                                  note: input.note)
            context.insert(walk)
            for dog in selectedProfiles {
                context.insert(WalkDogRecord(walkID: walk.id, dogID: dog.id, dogNameSnapshot: dog.name))
            }
            do { try context.save(); dismiss() }
            catch {
                context.rollback()
                errorMessage = "La balade n’a pas été enregistrée. Les valeurs saisies restent disponibles."
            }
        } catch WalkError.missingDog {
            errorMessage = "Sélectionnez au moins un chien."
        } catch WalkError.noteTooLong {
            errorMessage = "La note doit contenir au maximum 500 caractères."
        } catch {
            errorMessage = "La durée doit être positive, finie et ne pas dépasser 24 heures."
        }
    }
}
```

## `truffloTests/WalkDomainTests.swift`

Cible de tests unitaires seulement. Les 22 tests de ce fichier ont été exécutés hors iOS.

```swift
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import TruffloDomain
#else
@testable import trufflo
#endif

@Test func recordingAccruesConfirmedTime() throws {
    var walk = WalkProgress()
    try walk.accrue(seconds: 30)
    try walk.accrue(seconds: 15)
    #expect(walk.confirmedSeconds == 45)
}

@Test func pauseIsIdempotentAndCannotAccrue() throws {
    var walk = WalkProgress()
    try walk.accrue(seconds: 30)
    try walk.pause()
    try walk.pause()
    #expect(throws: WalkError.invalidTransition) { try walk.accrue(seconds: 10) }
    #expect(walk.confirmedSeconds == 30)
}

@Test func resumePreservesExistingDuration() throws {
    var walk = WalkProgress()
    try walk.accrue(seconds: 20)
    try walk.pause()
    try walk.resume()
    try walk.resume()
    try walk.accrue(seconds: 10)
    #expect(walk.confirmedSeconds == 30)
}

@Test func coldLaunchDoesNotInventElapsedTime() throws {
    var walk = WalkProgress()
    try walk.accrue(seconds: 42)
    let data = try JSONEncoder().encode(walk)
    var restored = try JSONDecoder().decode(WalkProgress.self, from: data)
    restored.recoverAfterColdLaunch()
    #expect(restored.phase == .interrupted)
    #expect(restored.confirmedSeconds == 42)
}

@Test func pausedSessionIsInterruptedOnColdLaunch() throws {
    var walk = WalkProgress()
    try walk.pause()
    walk.recoverAfterColdLaunch()
    #expect(walk.phase == .interrupted)
}

@Test func completedSessionStaysCompletedAfterColdLaunch() throws {
    var walk = WalkProgress()
    try walk.finish()
    try walk.finish()
    walk.recoverAfterColdLaunch()
    #expect(walk.phase == .completed)
    #expect(throws: WalkError.invalidTransition) { try walk.resume() }
}

@Test func discardedSessionCannotFinish() throws {
    var walk = WalkProgress()
    try walk.discard()
    #expect(throws: WalkError.invalidTransition) { try walk.finish() }
}

@Test(arguments: [-1.0, Double.nan, Double.infinity])
func invalidElapsedTimeIsRejected(seconds: Double) {
    var walk = WalkProgress()
    #expect(throws: WalkError.invalidDuration) { try walk.accrue(seconds: seconds) }
}

@Test func manualWalkDeduplicatesDogsWithoutMultiplyingDuration() throws {
    let dogA = UUID()
    let dogB = UUID()
    let input = try ManualWalkInput(dogIDs: [dogA, dogA, dogB], durationSeconds: 1800)
    #expect(input.dogIDs.count == 2)
    #expect(input.durationSeconds == 1800)
}

@Test func manualWalkRequiresADog() {
    #expect(throws: WalkError.missingDog) {
        try ManualWalkInput(dogIDs: [], durationSeconds: 600)
    }
}

@Test(arguments: [0.0, -1.0, Double.nan, Double.infinity, 86_401.0])
func manualWalkRejectsInvalidDuration(seconds: Double) {
    #expect(throws: WalkError.invalidDuration) {
        try ManualWalkInput(dogIDs: [UUID()], durationSeconds: seconds)
    }
}

@Test func manualNoteIsTrimmedAndLimited() throws {
    let input = try ManualWalkInput(dogIDs: [UUID()], durationSeconds: 60, note: "  Calme  ")
    #expect(input.note == "Calme")
    #expect(throws: WalkError.noteTooLong) {
        try ManualWalkInput(dogIDs: [UUID()], durationSeconds: 60, note: String(repeating: "a", count: 501))
    }
}

private func fix(_ longitude: Double, seconds: Double, accuracy: Double = 5) -> LocationFix {
    LocationFix(latitude: 0, longitude: longitude, horizontalAccuracy: accuracy,
                timestamp: Date(timeIntervalSince1970: 1_000 + seconds))
}

@Test func distanceIsUnavailableBeforeAnEdgeExists() {
    var track = TrackAccumulator()
    #expect(track.measuredDistance == nil)
    #expect(track.ingest(fix(0, seconds: 0)) == .anchor(segment: 1))
    #expect(track.measuredDistance == nil)
}

@Test func validGeometryAddsApproximateDistance() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    _ = track.ingest(fix(0.0001, seconds: 5))
    #expect(abs(track.distanceMeters - 11.1195) < 0.01)
    #expect(track.measuredEdgeCount == 1)
    #expect(!track.isPartial)
}

@Test func samePositionProducesARealZeroDistanceEdge() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    _ = track.ingest(fix(0, seconds: 5))
    #expect(track.measuredDistance == 0)
}

@Test func badAccuracyDoesNotBridgeUnknownMotion() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    #expect(track.ingest(fix(0.0001, seconds: 5, accuracy: 500)) == .rejected)
    #expect(track.ingest(fix(0.0002, seconds: 10)) == .anchor(segment: 2))
    #expect(track.distanceMeters == 0)
    #expect(track.isPartial)
}

@Test func largeTimeGapStartsANewSegment() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    #expect(track.ingest(fix(0.0001, seconds: 60)) == .anchor(segment: 2))
    #expect(track.measuredDistance == nil)
    #expect(track.isPartial)
}

@Test func impossibleJumpIsRejected() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    #expect(track.ingest(fix(10, seconds: 1)) == .rejected)
    #expect(track.distanceMeters == 0)
}

@Test func oldAndDuplicateFixesAreIgnored() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 10))
    #expect(track.ingest(fix(0.001, seconds: 10)) == .ignoredDuplicateOrOld)
    #expect(track.ingest(fix(0.001, seconds: 9)) == .ignoredDuplicateOrOld)
    #expect(!track.isPartial)
}

@Test func manualPauseDoesNotConnectCoordinates() {
    var track = TrackAccumulator()
    _ = track.ingest(fix(0, seconds: 0))
    track.breakSegment()
    #expect(track.ingest(fix(0.0001, seconds: 5)) == .anchor(segment: 2))
    #expect(!track.isPartial)
    #expect(track.measuredDistance == nil)
}

@Test func invalidCoordinatesAreRejected() {
    var track = TrackAccumulator()
    let point = LocationFix(latitude: 91, longitude: 0, horizontalAccuracy: 5, timestamp: Date())
    #expect(track.ingest(point) == .rejected)
    #expect(track.isPartial)
}

@Test func nonFiniteMetadataIsRejected() {
    var track = TrackAccumulator()
    #expect(track.ingest(fix(0, seconds: 0, accuracy: .nan)) == .rejected)
    #expect(track.ingest(fix(.infinity, seconds: 0)) == .rejected)
}
```

## `truffloTests/StorageTests.swift`

Cible de tests unitaires seulement. Exemple SwiftData à exécuter dans Xcode ; pas exécuté ici.

```swift
import Foundation
import SwiftData
import Testing
@testable import trufflo

@MainActor
@Test func manualWalkHasOneDurationAndTwoParticipants() throws {
    let container = try PersistenceFactory.make(inMemory: true)
    let context = container.mainContext
    let a = DogRecord(name: "Oslo", breedKind: "unknown")
    let b = DogRecord(name: "Nala", breedKind: "mixed")
    context.insert(a)
    context.insert(b)
    let walk = WalkRecord(endedAt: .now, durationSeconds: 1800, note: "")
    context.insert(walk)
    context.insert(WalkDogRecord(walkID: walk.id, dogID: a.id, dogNameSnapshot: a.name))
    context.insert(WalkDogRecord(walkID: walk.id, dogID: b.id, dogNameSnapshot: b.name))
    try context.save()
    let walks = try context.fetch(FetchDescriptor<WalkRecord>())
    let participants = try context.fetch(FetchDescriptor<WalkDogRecord>())
    #expect(walks.count == 1)
    #expect(walks[0].durationSeconds == 1800)
    #expect(participants.count == 2)
}
```

## `truffloUITests/StarterUITests.swift`

Cible UI seulement. Exemple de parcours à exécuter sur simulateur ; pas exécuté ici.

```swift
import XCTest

final class StarterUITests: XCTestCase {
    @MainActor
    func testCreateDogAndRecordManualWalk() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let addDog = app.buttons["dog.add"]
        XCTAssertTrue(addDog.waitForExistence(timeout: 5))
        addDog.tap()
        let name = app.textFields["dog.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Oslo")
        app.buttons["dog.save"].tap()
        let addWalk = app.buttons["walk.manual.add"]
        XCTAssertTrue(addWalk.waitForExistence(timeout: 5))
        addWalk.tap()
        let minutes = app.textFields["walk.minutes"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        minutes.tap()
        minutes.typeText("10")
        app.buttons["walk.save"].tap()
        let journal = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        journal.tap()
        let manualRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "walk.row.")
        ).firstMatch
        XCTAssertTrue(manualRow.waitForExistence(timeout: 5))
        XCTAssertTrue(manualRow.label.contains("Saisie manuelle"))
    }
}
```

## Contrôle isolé du domaine — facultatif

Ce manifeste n’est pas à ajouter à la cible de l’app. Il permet de reproduire le contrôle des règles dans un dossier indépendant. Copier exactement le fichier de domaine ci-dessus vers `Sources/TruffloDomain/WalkDomain.swift` et ses tests vers `Tests/TruffloDomainTests/WalkDomainTests.swift`, puis créer `Package.swift` :

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TruffloDomain",
    products: [.library(name: "TruffloDomain", targets: ["TruffloDomain"])],
    targets: [
        .target(name: "TruffloDomain"),
        .testTarget(name: "TruffloDomainTests", dependencies: ["TruffloDomain"])
    ]
)
```

Puis exécuter `swift test -j 2` dans ce dossier. Le `#if SWIFT_PACKAGE` des tests choisit automatiquement le bon import. Ce package sert à la vérification ; il ne rend pas SwiftUI ou SwiftData disponibles sous Linux.

## Limites à conserver visibles

Le journal M0 utilise des requêtes simples ; les recherches de liens dans les lignes ne sont pas une stratégie de performance pour de gros historiques. La localisation, le stockage des points et leur présentation seront séparés dans M1. Les migrations, export/suppressions ciblées, contrôle des sauvegardes, stockage écran verrouillé, catalogue de chaînes et vérification d’accessibilité ne sont pas terminés.

Le filtre initial reconnaît les sauts et les trous, pas encore la dérive stationnaire du vrai GPS. Les valeurs de seuil sont expérimentales. Le domaine ne fournit pas de driver d’horloge natif : le coordinateur doit alimenter les deltas monotones valides et ne pas reconstruire le temps après lancement à froid. Les futures transmissions serveur n’incluront pas automatiquement le tracé.
