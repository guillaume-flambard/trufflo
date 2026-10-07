import SwiftUI
import SwiftData

/// The last walk of Today as an object: a tile with its route drawn large, and
/// under it the dogs, the hour, the figures and the note (A2-REQ-06).
///
/// A card holds a real object, and a walk is one (ART-DIRECTION §3.3). The route is
/// the silhouette, not a map: it draws in no time, works with no network, and the
/// real map is one tap away in the walk itself, reached by a zoom out of this tile.
/// A walk declared by hand has no route, so the tile shows none rather than an
/// invented one.
///
/// The Journal keeps its timeline rows: a list of forty tiles would be a wall.
struct WalkTile: View {
    let walk: WalkRecord

    @Query private var participants: [WalkDogRecord]
    @Query private var points: [TrackPointRecord]
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]

    init(walk: WalkRecord) {
        self.walk = walk
        let walkID = walk.id
        _participants = Query(filter: #Predicate<WalkDogRecord> { $0.walkID == walkID })
        _points = Query(filter: #Predicate<TrackPointRecord> { $0.walkID == walkID },
                        sort: \.sequence, order: .forward)
    }

    private let shape = RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
    /// Space between the tile's edge and what it holds. The route's corners are the
    /// tile's corners minus this, which `ConcentricRectangle` computes.
    private let inset: CGFloat = 8

    private var isGPS: Bool { walk.source != .manual }
    private var date: Date { walk.endedAt ?? walk.startedAt }
    private var names: String {
        participants.map(\.dogNameSnapshot).sorted()
            .formatted(.list(type: .and).locale(TruffloLocale.french))
    }
    /// The face of the first dog of the walk that has a photo.
    private var leadPhoto: Data? {
        let ids = Set(participants.map(\.dogID))
        return dogs.first { ids.contains($0.id) && $0.photoData != nil }?.photoData
    }
    private var route: [TrackCoordinate]? {
        guard isGPS, points.count >= 2 else { return nil }
        let stride = max(points.count / 160, 1)
        return points.enumerated().compactMap { index, point in
            index % stride == 0 || index == points.count - 1
                ? TrackCoordinate(segment: point.segment, latitude: point.latitude, longitude: point.longitude)
                : nil
        }
    }
    private var figures: String {
        var parts = [WalkFormatting.minutes(walk.confirmedSeconds)]
        if isGPS, let meters = walk.recordedPathMeters { parts.append(WalkFormatting.distance(meters)) }
        return parts.joined(separator: ", ")
    }
    private var origin: String {
        "\(WalkFormatting.relativeDay(date)), \(isGPS ? "suivi GPS" : "saisie manuelle")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            if let route {
                TruffloRouteMap(points: route, cacheKey: "\(walk.id.uuidString)-\(walk.revision)-\(points.count)")
                    .frame(height: 150)
                    .clipShape(ConcentricRectangle())
            }
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                HStack(alignment: .center, spacing: TruffloTheme.Spacing.small) {
                    if let leadPhoto {
                        TruffloDogPortrait(name: names, photoData: leadPhoto, diameter: 44, aimsAtAnimal: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(names.isEmpty ? "Balade" : names)
                            .font(.truffloBodyHeavy)
                            .foregroundStyle(Color.truffloForest)
                        Text(origin)
                            .font(.truffloMeta)
                            .foregroundStyle(Color.truffloSlate)
                    }
                    Spacer(minLength: TruffloTheme.Spacing.small)
                    Text(WalkFormatting.time(date))
                        .font(.truffloMeta)
                        .monospacedDigit()
                        .foregroundStyle(Color.truffloSlate)
                }
                Text(figures)
                    .font(.truffloTitleHeavy)
                    .monospacedDigit()
                    .foregroundStyle(Color.truffloCharcoal)
                    .padding(.top, TruffloTheme.Spacing.xxSmall)
                if !walk.note.isEmpty {
                    Text(walk.note)
                        .font(.truffloBodyRegular)
                        .foregroundStyle(Color.truffloCharcoal)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.xSmall)
            .padding(.bottom, TruffloTheme.Spacing.xSmall)
        }
        .padding(inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerShape(shape)
        .background(Color.white, in: shape)
        // Depth declared once, as a soft shadow tinted with the page's own green (never a
        // grey one): the tile sits above the page without a border to say so.
        .shadow(color: Color.truffloForest.opacity(0.10), radius: 18, x: 0, y: 8)
        .shadow(color: Color.truffloForest.opacity(0.05), radius: 2, x: 0, y: 1)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("walk.row.\(walk.id.uuidString)")
    }

    private var spokenLabel: String {
        var parts = [names.isEmpty ? "Balade" : "Balade avec \(names)", isGPS ? "Suivi GPS" : "Saisie manuelle"]
        parts.append(WalkFormatting.dayAndTime(date))
        parts.append(figures)
        if !walk.note.isEmpty { parts.append(walk.note) }
        return parts.joined(separator: ", ")
    }
}
