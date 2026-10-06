import SwiftData
import SwiftUI

struct SharedWalkRoute: Hashable { let id: UUID }

/// A walk recorded by another member, as a journal card. Same reading order
/// as the person's own cards, with who recorded it said first. No silhouette
/// and no note: neither ever reaches this iPhone.
struct SharedWalkCard: View {
    let walk: SharedWalkRecord
    let authorName: String
    var possibleDuplicate = false

    private var date: Date { walk.endedAt }
    private var names: String {
        walk.dogNames.formatted(.list(type: .and).locale(Locale(identifier: "fr_FR")))
    }
    private var isGPS: Bool { walk.source != .manual }

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            HStack(spacing: TruffloTheme.Spacing.small) {
                TruffloDogPortrait(name: names.isEmpty ? "?" : names, photoData: nil, diameter: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(names.isEmpty ? "Balade" : names)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.truffloCharcoal)
                    Text("\(date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_FR")))), par \(authorName)")
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                }
            }
            Text(WalkFormatting.activityTitle(date))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.truffloForest)
            TruffloStatRow {
                TruffloStat("Durée", value: WalkFormatting.minutes(walk.confirmedSeconds), style: .title2)
                if isGPS, let meters = walk.recordedPathMeters {
                    TruffloStat("Distance", value: WalkFormatting.distance(meters), style: .title2)
                }
            }
            if possibleDuplicate {
                Label("Peut-être la même sortie qu'une des vôtres", systemImage: "square.on.square")
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
            }
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
            .strokeBorder(Color.truffloForest.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("shared.row.\(walk.id.uuidString)")
    }

    private var spokenLabel: String {
        var parts = [WalkFormatting.activityTitle(date), "enregistrée par \(authorName)"]
        if !names.isEmpty { parts.append("avec \(names)") }
        parts.append(WalkFormatting.dayAndTime(date))
        parts.append(WalkFormatting.minutes(walk.confirmedSeconds))
        if isGPS, let meters = walk.recordedPathMeters { parts.append(WalkFormatting.distance(meters)) }
        if possibleDuplicate { parts.append("peut-être la même sortie qu'une des vôtres") }
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
                        Text(WalkFormatting.activityTitle(walk.endedAt))
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.truffloForest)
                        Text("Enregistrée par \(author)").truffloSecondaryText()
                    }
                    TruffloStatRow {
                        TruffloStat("Durée", value: WalkFormatting.minutes(walk.confirmedSeconds), style: .title)
                        if walk.source != .manual, let meters = walk.recordedPathMeters {
                            TruffloStat("Distance", value: WalkFormatting.distance(meters), style: .title)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        WalkFactRow("Chiens", walk.dogNames.formatted(.list(type: .and).locale(Locale(identifier: "fr_FR"))))
                        WalkFactRow("Départ et retour", WalkFormatting.timeRange(walk.startedAt, walk.endedAt))
                        WalkFactRow("Mesure", WalkFormatting.quality(walk.quality))
                        if walk.source != .manual && walk.recordedPathMeters == nil {
                            WalkFactRow("Distance", "Non mesurée")
                        }
                        if let corrected = walk.correctedAt {
                            WalkFactRow("Corrigée", WalkFormatting.dayAndTime(corrected))
                        }
                    }
                    Text("Le tracé et la note restent sur l'iPhone de \(author). Seule cette personne peut corriger la balade.")
                        .truffloSecondaryText()
                }
                .padding(.horizontal, TruffloTheme.Spacing.large)
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
