import SwiftUI
import SwiftData

/// One balade as a card: who and when, the note, the figures in a grid, and the
/// tracé on a map at the bottom. The same card on Today and in the Journal, built
/// like an activity feed card (2026-10-07 review), so a balade looks like itself
/// wherever it appears.
///
/// A balade ajoutée has no tracé, so its card has no map rather than an invented one.
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

    var body: some View {
        // Built once per render: each build maps every point of the tracé.
        WalkCard(walk: walk,
                 shown: WalkPresentation(walk: walk, participants: participants, dogs: dogs, points: points),
                 pointCount: points.count)
    }
}

private struct WalkCard: View {
    let walk: WalkRecord
    let shown: WalkPresentation
    let pointCount: Int

    private let shape = RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)

    private var kind: String { shown.isTracked ? "balade suivie" : "balade ajoutée" }

    private var stats: [TruffloStatGrid.Item] {
        var items = [TruffloStatGrid.Item(label: "Durée", value: WalkFormatting.minutes(walk.confirmedSeconds))]
        if shown.isTracked, let meters = walk.recordedPathMeters {
            items.append(.init(label: "Distance", value: WalkFormatting.distance(meters)))
        }
        return items
    }

    var body: some View {
        // As in the mock-up: the map fills the right side and runs under the
        // words, melting into the card, so the words keep their width.
        ZStack(alignment: .trailing) {
            if let route = shown.route(maxPoints: WalkPresentation.picturePoints) {
                TruffloRouteMap(points: route, cacheKey: "\(walk.id.uuidString)-\(walk.revision)-\(pointCount)",
                                isVivid: true)
                    .frame(width: 200)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .black, location: 0.45)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .bottomTrailing) { faceInset }
            } else if shown.leadPhoto != nil {
                faceInset.frame(maxHeight: .infinity, alignment: .bottom)
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(WalkFormatting.relativeDay(shown.date).capitalizedFirst) · \(WalkFormatting.time(shown.date))",
                          systemImage: "clock")
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                        .lineLimit(1)
                    Text(shown.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .lineLimit(1)
                    if !walk.note.isEmpty {
                        Text(walk.note)
                            .font(.footnote)
                            .foregroundStyle(Color.truffloCharcoal.opacity(0.85))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    HStack(alignment: .top, spacing: TruffloTheme.Spacing.medium) {
                        ForEach(Array(stats.enumerated()), id: \.offset) { index, item in
                            if index > 0 {
                                Rectangle().fill(Color.truffloForest.opacity(0.15)).frame(width: 1, height: 36)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.value)
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.truffloForest)
                                    .lineLimit(1)
                                    .fixedSize()
                                Text(item.label)
                                    .font(.caption)
                                    .foregroundStyle(Color.truffloSlate)
                            }
                        }
                    }
                }
                .padding(TruffloTheme.Spacing.medium)
                .frame(width: 200, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .leading)
        .background(Color.white)
        .clipShape(shape)
        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("walk.row.\(walk.id.uuidString)")
    }

    /// The dog's face, small, in the corner of the map: whose balade it was.
    @ViewBuilder
    private var faceInset: some View {
        if let photo = shown.leadPhoto {
            TruffloDogThumbnail(name: shown.leadName ?? "", photoData: photo)
                .padding(TruffloTheme.Spacing.small)
        }
    }

    private var spokenLabel: String {
        let kind = shown.isTracked ? "Balade suivie" : "Balade ajoutée"
        var parts = [shown.names.isEmpty ? kind : "\(kind) avec \(shown.title)"]
        parts.append(WalkFormatting.dayAndTime(shown.date))
        parts.append(contentsOf: stats.map(\.value))
        if !walk.note.isEmpty { parts.append(walk.note) }
        return parts.joined(separator: ", ")
    }
}

/// One balade as a card of the Journal (2026-10-07 mock-up): the hour, who, the
/// note; a picture on the right (the tracé with the dog's face, or the dog's
/// photo for a balade ajoutée); the figures along the bottom.
struct JournalWalkTile: View {
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

    var body: some View {
        JournalWalkCard(walk: walk,
                        shown: WalkPresentation(walk: walk, participants: participants, dogs: dogs, points: points),
                        pointCount: points.count)
    }
}

private struct JournalWalkCard: View {
    let walk: WalkRecord
    let shown: WalkPresentation
    let pointCount: Int

    private let shape = RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
    private let pictureShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    private var stats: [(value: String, label: String)] {
        var items = [(WalkFormatting.minutes(walk.confirmedSeconds), "Durée")]
        if shown.isTracked, let meters = walk.recordedPathMeters {
            items.append((WalkFormatting.distance(meters), "Distance"))
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(WalkFormatting.time(shown.date))
                    } icon: {
                        Image(systemName: "figure.walk").foregroundStyle(Color.truffloForest)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.truffloSlate)
                    Text(shown.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                        .lineLimit(1)
                    if !walk.note.isEmpty {
                        Text(walk.note)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.42, green: 0.42, blue: 0.42))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                picture
            }
            HStack(alignment: .top, spacing: TruffloTheme.Spacing.medium) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle().fill(Color.truffloForest.opacity(0.15)).frame(width: 1, height: 34)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.value)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.truffloForest)
                        Text(item.label)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.truffloSlate)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: shape)
        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("walk.row.\(walk.id.uuidString)")
    }

    /// The tracé with the dog's face in its corner, or the dog's photo alone for a
    /// balade ajoutée, or nothing: never an invented map.
    @ViewBuilder
    private var picture: some View {
        if let route = shown.route(maxPoints: WalkPresentation.picturePoints) {
            TruffloRouteMap(points: route, cacheKey: "\(walk.id.uuidString)-\(walk.revision)-\(pointCount)",
                            isVivid: true)
                .frame(width: 118, height: 92)
                .clipShape(pictureShape)
                .overlay(alignment: .bottomTrailing) {
                    if let photo = shown.leadPhoto {
                        TruffloDogThumbnail(name: shown.leadName ?? "", photoData: photo, side: 40)
                            .padding(6)
                    }
                }
        } else if let photo = shown.leadPhoto {
            TruffloDogThumbnail(name: shown.leadName ?? "", photoData: photo, side: 92, width: 118, bordered: false)
        }
    }

    private var spokenLabel: String {
        let kind = shown.isTracked ? "Balade suivie" : "Balade ajoutée"
        var parts = [shown.names.isEmpty ? kind : "\(kind) avec \(shown.title)"]
        parts.append(WalkFormatting.dayAndTime(shown.date))
        parts.append(contentsOf: stats.map(\.value))
        if !walk.note.isEmpty { parts.append(walk.note) }
        return parts.joined(separator: ", ")
    }
}
