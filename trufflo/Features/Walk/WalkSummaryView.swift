import SwiftUI
import SwiftData

/// The post-walk summary (PRD "Bilan"): what was recorded, read back from the
/// store, plus the one thing the live screen deliberately does not offer, a note.
///
/// Content is warm and opaque here: the person has stopped walking, the map is a
/// picture of what happened, and reading is allowed again. Nothing is recomputed:
/// duration, distance and quality are the stored values.
@MainActor
struct WalkSummaryView: View {
    @Environment(\.modelContext) private var context

    @Query private var matches: [WalkRecord]
    @Query private var participants: [WalkDogRecord]
    @Query private var points: [TrackPointRecord]
    @Query private var dogs: [DogRecord]

    @State private var note = ""
    @State private var hasLoadedNote = false
    @State private var saveError: String?
    /// A finished walk is framed once and never chases the camera afterwards.
    @State private var isFollowingTrack = false

    private let walkID: UUID
    private let onDone: () -> Void

    init(walkID: UUID, onDone: @escaping () -> Void) {
        self.walkID = walkID
        self.onDone = onDone
        _matches = Query(filter: #Predicate<WalkRecord> { $0.id == walkID })
        _participants = Query(filter: #Predicate<WalkDogRecord> { $0.walkID == walkID })
        _points = Query(filter: #Predicate<TrackPointRecord> { $0.walkID == walkID },
                        sort: \.sequence, order: .forward)
    }

    var body: some View {
        NavigationStack {
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
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // The media runs under the bar; the button floats over it in glass.
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé", action: saveAndClose)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("walk.summary.done")
                }
            }
            .tint(Color.truffloForest)
            .alert("Note non enregistrée", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - Content

    /// A recorded outing opens on its route. One without a usable route (a GPS walk
    /// that kept fewer than two points) never shows a map that pretends to be one:
    /// the dog stands in the same place instead, at the same height, so the layout
    /// does not jump between the two.
    private func content(for walk: WalkRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(for: walk)

                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                        Text("Balade terminée")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.truffloSage)
                        Text(title)
                            .font(.system(.title, design: .rounded, weight: .heavy))
                            .foregroundStyle(Color.truffloForest)
                        if let endedAt = walk.endedAt {
                            Text(WalkFormatting.dayAndTime(endedAt))
                                .font(.footnote)
                                .foregroundStyle(Color.truffloSlate)
                        }
                    }

                    TruffloStatRow {
                        TruffloStat("Durée", value: WalkFormatting.clock(walk.confirmedSeconds))
                        if let meters = walk.recordedPathMeters {
                            TruffloStat("Distance", value: WalkFormatting.distance(meters))
                        }
                    }

                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                        WalkSectionTitle("Note")
                        TextField("Comment s'est passée la balade ?", text: $note, axis: .vertical)
                            .font(.body)
                            .lineLimit(3...8)
                            .padding(TruffloTheme.Spacing.small)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.truffloForest.opacity(0.1), lineWidth: 1))
                            .accessibilityIdentifier("walk.summary.note")
                    }
                    .padding(.top, TruffloTheme.Spacing.medium)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.truffloForest.opacity(0.12)).frame(height: 1)
                    }

                    // Quiet: one line of what the measure is, and a gap named as a gap.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WalkFormatting.quality(walk.quality))
                            .font(.footnote)
                            .foregroundStyle(Color.truffloSlate)
                        if let hint = qualityHint(for: walk.quality) {
                            Text(hint)
                                .font(.footnote)
                                .foregroundStyle(Color.truffloSlate)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.large)
                .padding(.top, TruffloTheme.Spacing.large)
                .padding(.bottom, TruffloTheme.Spacing.xLarge)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Read once: a resumed summary must not overwrite what is being typed.
            guard !hasLoadedNote else { return }
            note = walk.note
            hasLoadedNote = true
        }
    }

    @ViewBuilder
    private func hero(for walk: WalkRecord) -> some View {
        if trackCoordinates.count >= 2 {
            TruffloTrackMap(points: trackCoordinates,
                            isLive: false,
                            showsMarkers: false,
                            isFollowing: $isFollowingTrack)
                .frame(height: 340)
                .accessibilityIdentifier("walk.summary.map")
        } else if let photo = leadDog?.photoData {
            let name = dogNames.first ?? "Balade"
            TruffloDogHero(name: name, photoData: photo, height: 340)
        } else {
            // No route and no photo: no stand-in. The page opens on the words.
            Color.clear.frame(height: TruffloTheme.Spacing.large)
        }
    }

    private var title: String {
        dogNames.isEmpty
            ? "Balade"
            : dogNames.formatted(.list(type: .and).locale(TruffloLocale.french))
    }

    /// The first participant still on the device. A deleted profile leaves its name
    /// in the walk and nothing else, so the hero then falls back to the initial.
    private var leadDog: DogRecord? {
        let ids = participants.map(\.dogID)
        return dogs.first { ids.contains($0.id) }
    }

    private func measurement(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.truffloForest)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(Color.truffloSlate)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Data

    private var trackCoordinates: [TrackCoordinate] {
        points.map { TrackCoordinate(segment: $0.segment, latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var dogNames: [String] {
        participants.map(\.dogNameSnapshot).sorted()
    }

    /// Canonical microcopy: a gap is named as a gap, never papered over.
    private func qualityHint(for quality: WalkQuality) -> String? {
        switch quality {
        case .gpsPartial: "Une partie du parcours n'a pas été mesurée."
        case .unavailable: "Aucun point n'a été accepté. La durée seule est conservée."
        case .gpsRecorded, .manual: nil
        }
    }

    // MARK: - Actions

    /// Writes the note only when it changed, then closes. A failed write keeps the
    /// screen open: the walk itself is already saved, only the note is at stake.
    private func saveAndClose() {
        guard let walk = matches.first else {
            onDone()
            return
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == walk.note {
            onDone()
            return
        }
        do {
            try JournalRepository(context: context).updateWalkNote(walk.id, note: note)
            onDone()
        } catch WalkError.noteTooLong {
            saveError = "La note doit contenir au maximum 500 caractères."
        } catch {
            saveError = "La note n'a pas été enregistrée. La balade, elle, est bien conservée."
        }
    }
}
