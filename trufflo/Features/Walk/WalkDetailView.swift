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
                TruffloEmptyStateView(
                    imageName: "EmptyWalk",
                    title: "Cette balade n'existe plus",
                    description: "Elle a été retirée de cet appareil."
                )
            }
        }
        .navigationTitle("Balade")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if trackCoordinates.count >= 2 {
                    TruffloTrackMap(points: trackCoordinates,
                                    isLive: false,
                                    showsMarkers: false,
                                    isFollowing: $isFollowingTrack)
                        .frame(height: 280)
                        .accessibilityIdentifier("walk.detail.map")
                }

                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        HStack(spacing: TruffloTheme.Spacing.small) {
                            TruffloDogPortrait(name: names.first ?? "?", photoData: leadDog?.photoData, diameter: 40)
                            VStack(alignment: .leading, spacing: 0) {
                                if names.isEmpty {
                                    Text("Aucun chien associé à cette balade.")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.truffloSlate)
                                } else {
                                    Text(names.formatted(.list(type: .and).locale(Locale(identifier: "fr_FR"))))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.truffloCharcoal)
                                }
                                Text(WalkFormatting.dayAndTime(date))
                                    .font(.footnote)
                                    .foregroundStyle(Color.truffloSlate)
                            }
                        }
                        Text(WalkFormatting.activityTitle(date))
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.truffloForest)
                    }

                    TruffloStatRow {
                        TruffloStat("Durée", value: WalkFormatting.minutes(walk.confirmedSeconds))
                        TruffloStat("Distance", value: WalkFormatting.distance(walk.recordedPathMeters),
                                    dimmed: walk.recordedPathMeters == nil)
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
                        WalkSectionTitle("Détails")
                            .padding(.bottom, TruffloTheme.Spacing.xSmall)
                        WalkFactRow("Fin de la balade",
                                    walk.endedAt.map(WalkFormatting.dayAndTime) ?? "En cours")
                        WalkFactRow("Origine", walk.source == .manual ? "Saisie manuelle" : "Suivi GPS")
                        WalkFactRow("Qualité", qualityText(walk.quality))
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
                        .accessibilityIdentifier("walk.delete")
                        .accessibilityLabel(accessibilityDeleteLabel(for: walk))
                        Text("La balade, les chiens qui y figurent et les points enregistrés sont retirés de cet appareil.")
                            .font(.footnote)
                            .foregroundStyle(Color.truffloSlate)
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.medium)
                .padding(.top, TruffloTheme.Spacing.large)
                .padding(.bottom, TruffloTheme.Spacing.xLarge)
            }
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
