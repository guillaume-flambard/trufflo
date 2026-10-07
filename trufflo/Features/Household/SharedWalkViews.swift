import SwiftData
import SwiftUI

struct SharedWalkRoute: Hashable { let id: UUID }

/// A walk recorded by another member, as a line of the timeline. Who
/// recorded it is said in the meta line. No route and no note: neither ever
/// reaches this iPhone.
struct SharedWalkCard: View {
    let walk: SharedWalkRecord
    let authorName: String
    var possibleDuplicate = false
    /// Outside the journal's day groups the line also says which day.
    var showsDay = false

    private var date: Date { walk.endedAt }
    private var names: String {
        walk.dogNames.formatted(.list(type: .and).locale(TruffloLocale.french))
    }
    private var isGPS: Bool { walk.source != .manual }
    private var figures: [String] {
        var parts = [WalkFormatting.minutes(walk.confirmedSeconds)]
        if isGPS, let meters = walk.recordedPathMeters { parts.append(WalkFormatting.distance(meters)) }
        return parts
    }

    var body: some View {
        // The row of my own last balade, the author named after the time.
        VStack(alignment: .leading, spacing: 5) {
            Label("\(WalkFormatting.dayDotTime(date)) · par \(authorName)", systemImage: "clock")
                .font(.system(size: 12))
                .foregroundStyle(Color.truffloSlate)
            // The author's title when they gave one, as on their own Journal.
            Text(!walk.title.isEmpty ? walk.title : (names.isEmpty ? "Balade" : names))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                .lineLimit(1)
            HStack(spacing: 10) {
                Text(figures.joined(separator: " · "))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.truffloForest)
                if let mood = walk.mood {
                    Label(mood.label, systemImage: mood.systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.truffloSlate)
                }
            }
            if possibleDuplicate {
                Label("Peut-être la même balade qu'une des vôtres", systemImage: "square.on.square")
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
            }
        }
        .truffloBoardCard(padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("shared.row.\(walk.id.uuidString)")
    }

    private var spokenLabel: String {
        var parts = [names.isEmpty ? "Balade" : "Balade avec \(names)", "enregistrée par \(authorName)"]
        parts.append(WalkFormatting.dayAndTime(date))
        parts.append(contentsOf: figures)
        if possibleDuplicate { parts.append("peut-être la même balade qu'une des vôtres") }
        return parts.joined(separator: ", ")
    }
}

/// The detail of another member's walk: facts only, read-only. Only the
/// person who recorded it can correct it (PRD F08).
struct SharedWalkDetailView: View {
    let walkID: UUID
    @Query private var walks: [SharedWalkRecord]
    @Query private var members: [HouseholdMemberRecord]

    init(walkID: UUID) {
        self.walkID = walkID
        _walks = Query(filter: #Predicate<SharedWalkRecord> { $0.id == walkID })
    }

    var body: some View {
        ScrollView {
            if let walk = walks.first {
                let author = members.first { $0.userID == walk.authorID }?.displayName ?? "un membre du foyer"
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                        Text(walk.dogNames.formatted(.list(type: .and).locale(TruffloLocale.french)))
                            .font(.system(.title, design: .rounded, weight: .heavy))
                            .foregroundStyle(Color.truffloForest)
                        Text("\(WalkFormatting.relativeDayAndTime(walk.endedAt).capitalizedFirst), par \(author)")
                            .truffloSecondaryText()
                    }
                    TruffloStatRow {
                        TruffloStat("Durée", value: WalkFormatting.minutes(walk.confirmedSeconds), style: .title)
                        if walk.source != .manual, let meters = walk.recordedPathMeters {
                            TruffloStat("Distance", value: WalkFormatting.distance(meters), style: .title)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        WalkFactRow("Départ et retour", WalkFormatting.timeRange(walk.startedAt, walk.endedAt))
                        WalkFactRow("Mesure", WalkFormatting.quality(walk.quality))
                        if walk.recordedPathMeters == nil || walk.source == .manual {
                            WalkFactRow("Distance", "Non mesurée")
                        }
                        if let corrected = walk.correctedAt {
                            WalkFactRow("Corrigée", WalkFormatting.dayAndTime(corrected))
                        }
                    }
                    Text("Le tracé et la note restent sur l'iPhone de \(author). Seule cette personne peut corriger la balade.")
                        .truffloSecondaryText()
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.vertical, TruffloTheme.Spacing.medium)
            } else {
                TruffloNotice(title: "Balade introuvable",
                              message: "Elle a été supprimée par la personne qui l'avait enregistrée, ou vous avez quitté le foyer.")
            }
        }
        .navigationTitle("Balade du foyer")
        .navigationBarTitleDisplayMode(.inline)
        .truffloScreen()
    }
}
