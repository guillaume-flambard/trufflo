import SwiftUI
import SwiftData

/// One balade as a card of the Journal (2026-10-07 mock-up): the hour, who, the
/// note; a picture on the right (the tracé with the dog's face, or the dog's
/// photo for a balade ajoutée); the figures along the bottom.
struct JournalWalkTile: View {
    let walk: WalkRecord

    @Query private var participants: [WalkDogRecord]
    @Query private var points: [TrackPointRecord]
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]
    @Query private var photos: [WalkPhotoRecord]

    init(walk: WalkRecord) {
        self.walk = walk
        let walkID = walk.id
        _photos = Query(filter: #Predicate<WalkPhotoRecord> { $0.walkID == walkID }, sort: \.createdAt)
        _participants = Query(filter: #Predicate<WalkDogRecord> { $0.walkID == walkID })
        _points = Query(filter: #Predicate<TrackPointRecord> { $0.walkID == walkID },
                        sort: \.sequence, order: .forward)
    }

    var body: some View {
        JournalWalkCard(walk: walk,
                        shown: WalkPresentation(walk: walk, participants: participants, dogs: dogs, points: points),
                        pointCount: points.count,
                        firstPhoto: photos.first?.data)
    }
}

private struct JournalWalkCard: View {
    let walk: WalkRecord
    let shown: WalkPresentation
    let pointCount: Int
    let firstPhoto: Data?

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
                    .font(.system(size: 12))
                    .foregroundStyle(Color.truffloSlate)
                    Text(shown.heading)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
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
            HStack(alignment: .center, spacing: TruffloTheme.Spacing.medium) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle().fill(Color.truffloForest.opacity(0.15)).frame(width: 1, height: 34)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.value)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.truffloForest)
                        Text(item.label)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.truffloSlate)
                    }
                }
                Spacer(minLength: 0)
                if let mood = walk.mood {
                    Label(mood.label, systemImage: mood.systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.truffloCharcoal)
                        .labelStyle(MoodLabelStyle())
                }
            }
        }
        .padding(12)
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
                .frame(width: 112, height: 84)
                .clipShape(pictureShape)
                .overlay(alignment: .bottomTrailing) {
                    if let photo = shown.leadPhoto {
                        TruffloDogThumbnail(name: shown.leadName ?? "", photoData: photo, side: 40)
                            .padding(6)
                    }
                }
        } else if let photo = firstPhoto ?? shown.leadPhoto {
            TruffloDogThumbnail(name: shown.leadName ?? "", photoData: photo, side: 84, width: 112, bordered: false)
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

/// The mood at the corner of a journal card: its symbol in forest, its words.
private struct MoodLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 18)).foregroundStyle(Color.truffloForest)
            configuration.title
        }
    }
}
