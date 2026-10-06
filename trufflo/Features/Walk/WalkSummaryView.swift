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
            .navigationTitle("Bilan de la balade")
            .navigationBarTitleDisplayMode(.inline)
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

    private func content(for walk: WalkRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
                if trackCoordinates.count >= 2 {
                    TruffloTrackMap(points: trackCoordinates,
                                    isLive: false,
                                    showsMarkers: false,
                                    isFollowing: $isFollowingTrack)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card,
                                                    style: .continuous))
                        .accessibilityIdentifier("walk.summary.map")
                }

                TruffloCard {
                    HStack(alignment: .firstTextBaseline, spacing: TruffloTheme.Spacing.medium) {
                        measurement(value: WalkFormatting.clock(walk.confirmedSeconds), caption: "Durée")
                        Rectangle()
                            .fill(Color.truffloForest.opacity(0.14))
                            .frame(width: 1, height: 36)
                            .accessibilityHidden(true)
                        measurement(value: WalkFormatting.distance(walk.recordedPathMeters),
                                    caption: "Distance",
                                    dimmed: walk.recordedPathMeters == nil)
                    }
                    .padding(.vertical, TruffloTheme.Spacing.xxSmall)
                }

                TruffloCard {
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        LabeledContent("Qualité") {
                            Text(WalkFormatting.quality(walk.quality))
                                .font(.truffloSubheadline)
                                .foregroundStyle(Color.truffloForest)
                        }
                        .font(.truffloBody)
                        if let hint = qualityHint(for: walk.quality) {
                            Text(hint)
                                .font(.truffloCaption)
                                .foregroundStyle(Color.truffloSlate)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !dogNames.isEmpty {
                            HStack(spacing: TruffloTheme.Spacing.xSmall) {
                                ForEach(dogNames, id: \.self) { name in
                                    TruffloBadge(name, icon: "pawprint.fill", style: .sage)
                                }
                            }
                        }
                    }
                }

                TruffloCard {
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                        Text("Note")
                            .font(.truffloHeadline)
                            .foregroundStyle(Color.truffloForest)
                        TextField("Comment s'est passée la balade ?", text: $note, axis: .vertical)
                            .font(.truffloBody)
                            .lineLimit(3...6)
                            .accessibilityIdentifier("walk.summary.note")
                    }
                }
            }
            .padding(TruffloTheme.Spacing.medium)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Read once: a resumed summary must not overwrite what is being typed.
            guard !hasLoadedNote else { return }
            note = walk.note
            hasLoadedNote = true
        }
    }

    private func measurement(value: String, caption: String, dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(dimmed ? Color.truffloCharcoal.opacity(0.55) : Color.truffloForest)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.truffloSlate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
