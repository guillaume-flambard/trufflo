import SwiftUI
import SwiftData

/// One walk as an activity card, the only card in the app because a walk is a
/// real object: who and when, a name from the time of day, the figures, the
/// route silhouette when there is one, the start of the note.
///
/// The card reads its own points and dogs, so a list renders only the cards on
/// screen. A declared walk has no silhouette and no distance: it shows neither,
/// rather than an empty field that looks like a route that failed to load.
struct WalkActivityCard: View {
    let walk: WalkRecord
    /// The journal groups cards under a day heading, so its cards show the time
    /// alone; elsewhere the card says which day.
    var showsDay = true

    @Query private var participants: [WalkDogRecord]
    @Query private var points: [TrackPointRecord]
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]

    init(walk: WalkRecord, showsDay: Bool = true) {
        self.walk = walk
        self.showsDay = showsDay
        let walkID = walk.id
        _participants = Query(filter: #Predicate<WalkDogRecord> { $0.walkID == walkID })
        _points = Query(filter: #Predicate<TrackPointRecord> { $0.walkID == walkID },
                        sort: \.sequence, order: .forward)
    }

    private var isGPS: Bool { walk.source != .manual }
    private var whenText: String {
        showsDay ? WalkFormatting.relativeDayAndTime(date)
                 : date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_FR")))
    }
    private var date: Date { walk.endedAt ?? walk.startedAt }
    private var names: String {
        participants.map(\.dogNameSnapshot).sorted()
            .formatted(.list(type: .and).locale(Locale(identifier: "fr_FR")))
    }
    private var leadDog: DogRecord? {
        let ids = Set(participants.map(\.dogID))
        return dogs.first { ids.contains($0.id) }
    }
    private var coordinates: [TrackCoordinate] {
        // A silhouette needs a few hundred points at most.
        let stride = max(points.count / 300, 1)
        return points.enumerated().compactMap { index, point in
            index % stride == 0 || index == points.count - 1
                ? TrackCoordinate(segment: point.segment, latitude: point.latitude, longitude: point.longitude)
                : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            HStack(spacing: TruffloTheme.Spacing.small) {
                TruffloDogPortrait(name: names.isEmpty ? "?" : names,
                                   photoData: leadDog?.photoData, diameter: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(names.isEmpty ? "Balade" : names)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.truffloCharcoal)
                    Text(isGPS ? whenText : "\(whenText), saisie manuelle")
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

            if isGPS, coordinates.count >= 2 {
                TruffloRouteSilhouette(points: coordinates)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous))
            }

            if !walk.note.isEmpty {
                Text(walk.note)
                    .font(.subheadline)
                    .foregroundStyle(Color.truffloCharcoal)
                    .lineLimit(3)
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
        .accessibilityIdentifier("walk.row.\(walk.id.uuidString)")
    }

    /// The origin is spoken in words because the card shows it only in passing.
    private var spokenLabel: String {
        var parts = [WalkFormatting.activityTitle(date), isGPS ? "Suivi GPS" : "Saisie manuelle"]
        if !names.isEmpty { parts.append("avec \(names)") }
        parts.append(WalkFormatting.dayAndTime(date))
        parts.append(WalkFormatting.minutes(walk.confirmedSeconds))
        if isGPS, let meters = walk.recordedPathMeters { parts.append(WalkFormatting.distance(meters)) }
        if !walk.note.isEmpty { parts.append(walk.note) }
        return parts.joined(separator: ", ")
    }
}
