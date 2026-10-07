import SwiftUI
import SwiftData

/// One recorded walk, read in full (PRD F05), with a targeted delete.
///
/// An absent distance is written "Non mesurée", never "0": a missing measurement
/// and a measured zero are different facts and the UI must not merge them.
@MainActor
struct WalkDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var matches: [WalkRecord]
    @Query private var participants: [WalkDogRecord]
    @Query private var points: [TrackPointRecord]
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]

    @State private var showDeleteConfirmation = false
    @State private var routeFile: SharedFile?
    @State private var showCorrection = false
    @State private var storageError: String?
    /// A finished walk is framed once and never chases the camera afterwards.
    @State private var isFollowingTrack = false

    init(walkID: UUID) {
        _matches = Query(filter: #Predicate<WalkRecord> { $0.id == walkID })
        _participants = Query(filter: #Predicate<WalkDogRecord> { $0.walkID == walkID })
        _points = Query(filter: #Predicate<TrackPointRecord> { $0.walkID == walkID },
                        sort: \.sequence, order: .forward)
    }

    var body: some View {
        Group {
            if let walk = matches.first {
                content(for: walk)
            } else {
                TruffloNotice(title: "Cette balade n'existe plus", message: "Elle a été retirée de cet iPhone depuis un autre écran.", actionTitle: "Revenir au journal") { dismiss() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .truffloScreen()
        .alert("Modification impossible", isPresented: Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )) {
            Button("Fermer", role: .cancel) {}
        } message: {
            Text(storageError ?? "")
        }
    }

    /// The walk read in full, laid out like an activity: the route first when
    /// there is one, then who and when, a name from the time of day, the
    /// figures, the note, and the facts about the measurement in plain rows.
    @ViewBuilder
    private func content(for walk: WalkRecord) -> some View {
        let names = participants.map(\.dogNameSnapshot).sorted()
        let date = walk.endedAt ?? walk.startedAt
        let hasMap = trackCoordinates.count >= 2
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hasMap {
                    TruffloTrackMap(points: trackCoordinates,
                                    isLive: false,
                                    showsMarkers: false,
                                    isFollowing: $isFollowingTrack)
                        .frame(height: 340)
                        .accessibilityIdentifier("walk.detail.map")
                }

                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    HStack(alignment: .top, spacing: TruffloTheme.Spacing.medium) {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                            // The dogs are the title; the hour is a fact, not a name.
                            Text(names.isEmpty ? "Balade" : names.formatted(.list(type: .and).locale(TruffloLocale.french)))
                                .font(.system(.title, design: .rounded, weight: .heavy))
                                .foregroundStyle(Color.truffloForest)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(walk.source == .manual
                                 ? "\(WalkFormatting.relativeDayAndTime(date).capitalizedFirst), balade ajoutée"
                                 : WalkFormatting.relativeDayAndTime(date).capitalizedFirst)
                                .font(.subheadline)
                                .foregroundStyle(Color.truffloSlate)
                            if names.isEmpty {
                                Text("Aucun chien associé à cette balade.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.truffloSlate)
                            }
                        }
                        Spacer(minLength: 0)
                        // A face only when there is a photo: no initial on a disc.
                        if let photo = leadDog?.photoData {
                            TruffloDogPortrait(name: names.first ?? "", photoData: photo, diameter: 56)
                        }
                    }

                    // An absent distance is not a figure: it is said in the
                    // facts below, never set in large type next to the duration.
                    TruffloStatRow {
                        TruffloStat("Durée", value: WalkFormatting.minutes(walk.confirmedSeconds))
                        if let meters = walk.recordedPathMeters {
                            TruffloStat("Distance", value: WalkFormatting.distance(meters))
                        }
                    }

                    if !walk.note.isEmpty {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                            WalkSectionTitle("Note")
                            Text(walk.note)
                                .font(.body)
                                .foregroundStyle(Color.truffloCharcoal)
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        WalkFactRow("Mesure", WalkFormatting.quality(walk.quality))
                        if walk.recordedPathMeters == nil {
                            WalkFactRow("Distance", "Non mesurée")
                        }
                        if walk.source != .manual, let endedAt = walk.endedAt {
                            WalkFactRow("Départ et retour", WalkFormatting.timeRange(walk.startedAt, endedAt))
                        } else {
                            WalkFactRow("Fin de la balade",
                                        walk.endedAt.map(WalkFormatting.relativeDayAndTime) ?? "En cours")
                        }
                        if let correctedAt = walk.correctedAt {
                            WalkFactRow("Corrigée", WalkFormatting.relativeDayAndTime(correctedAt))
                        }
                    }

                    if walk.phase == .completed {
                        Button {
                            showCorrection = true
                        } label: {
                            Label("Corriger la balade", systemImage: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.truffloForest)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .truffloTap()
                        .accessibilityIdentifier("walk.correct")
                    }

                    if walk.source != .manual && trackCoordinates.count >= 2 {
                        Button {
                            exportRoute(of: walk)
                        } label: {
                            Label("Exporter le tracé (GPX)", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.truffloForest)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .truffloTap()
                        .accessibilityIdentifier("walk.export.gpx")
                    }

                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Text("Supprimer la balade")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.truffloDanger)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .truffloTap(.impact(weight: .medium))
                        .accessibilityIdentifier("walk.delete")
                        .accessibilityLabel(accessibilityDeleteLabel(for: walk))
                        Text("La balade, les chiens qui y figurent et les points enregistrés sont retirés de cet appareil.")
                            .font(.footnote)
                            .foregroundStyle(Color.truffloSlate)
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.top, TruffloTheme.Spacing.large)
                .padding(.bottom, TruffloTheme.Spacing.xLarge)
            }
        }
        // The route runs under the bar, edge to edge; the back button floats in glass.
        .ignoresSafeArea(edges: hasMap ? .top : [])
        // A walk declared by hand has no route to open on: the page takes the same
        // mint aura as the dog's screens instead of a bare sand head.
        .background(alignment: .top) {
            if !hasMap {
                TruffloDogAura(photoData: nil)
                    .frame(height: 360)
                    .ignoresSafeArea(edges: .top)
            }
        }
        // The bar never draws a title or a band: the dogs' names below are the
        // title, as on the profile, so both kinds of walk open the same way.
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .navigationTitle("")
        .sheet(isPresented: $showCorrection) {
            WalkCorrectionView(walk: walk, participants: participants,
                               existingDogIDs: Set(dogs.map(\.id)))
        }
        .sheet(item: $routeFile) { file in
            ShareSheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Supprimer cette balade ?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) { delete(walkID: walk.id) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La balade, ses participants et ses points enregistrés seront retirés de cet appareil.")
        }
    }

    private var leadDog: DogRecord? {
        let ids = Set(participants.map(\.dogID))
        return dogs.first { ids.contains($0.id) }
    }

    // MARK: - Formatting

    /// A manual entry has no coordinates at all, so it gets no map section rather
    /// than an empty one.
    private var trackCoordinates: [TrackCoordinate] {
        points.map { TrackCoordinate(segment: $0.segment, latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = (seconds / 60).formatted(.number.precision(.fractionLength(0...1)))
        return "\(minutes) min"
    }

    private func distanceText(_ meters: Double) -> String {
        if meters >= 1000 {
            let kilometers = (meters / 1000).formatted(.number.precision(.fractionLength(1...2)))
            return "\(kilometers) km"
        }
        let rounded = meters.formatted(.number.precision(.fractionLength(0)))
        return "\(rounded) m"
    }

    private func qualityText(_ quality: WalkQuality) -> String {
        switch quality {
        case .gpsRecorded: "Mesurée par GPS"
        case .gpsPartial: "Mesure partielle"
        case .manual: "Déclarée à la main"
        case .unavailable: "Non mesurée"
        }
    }

    private func accessibilityDeleteLabel(for walk: WalkRecord) -> String {
        guard let endedAt = walk.endedAt else { return "Supprimer la balade en cours" }
        let date = endedAt.formatted(.dateTime.day().month())
        return "Supprimer la balade du \(date)"
    }

    /// One walk's route as a GPX file. Read back from the export path, so the
    /// file is the same one the full journal export would contain.
    private func exportRoute(of walk: WalkRecord) {
        do {
            guard let exported = try JournalRepository(context: context).exportWalks()
                    .first(where: { $0.id == walk.id }),
                  let gpx = WalkExport.gpx(exported) else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(WalkExport.gpxFileName(for: exported))
            try Data(gpx.utf8).write(to: url, options: .atomic)
            routeFile = SharedFile(url: url)
        } catch {
            storageError = "Le tracé n'a pas pu être exporté."
        }
    }

    private func delete(walkID: UUID) {
        do {
            try JournalRepository(context: context).deleteWalk(walkID)
            dismiss()
        } catch JournalError.walkMissing {
            storageError = "Cette balade n'existe plus."
        } catch {
            storageError = "La balade n'a pas été supprimée. Les données précédentes ont été conservées."
        }
    }
}

/// A section heading in the walk screens, the same everywhere.
struct WalkSectionTitle: View {
    private let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(Color.truffloForest)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One fact about a walk: a label and its value on one line, separated by a
/// hairline from the next. The value wraps under the label at large sizes.
struct WalkFactRow: View {
    private let label: String
    private let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(Color.truffloSlate)
                Spacer(minLength: TruffloTheme.Spacing.small)
                Text(value).foregroundStyle(Color.truffloCharcoal).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(Color.truffloSlate)
                Text(value).foregroundStyle(Color.truffloCharcoal)
            }
        }
        .font(.subheadline)
        .padding(.vertical, TruffloTheme.Spacing.small)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.truffloForest.opacity(0.1)).frame(height: 1)
        }
    }
}
