import SwiftUI
import SwiftData

/// One walk as a line of the journal's timeline: the hour in its own column,
/// then who walked, how it was captured, and the figures. Rows sit on the
/// page, separated by a hairline, not boxed in a card: the day is the
/// container, the walk is a line in it.
///
/// No face is drawn when there is no photo, and no title is invented from the
/// hour: the dogs' names are the title, the hour is in the margin.
struct WalkActivityCard: View {
    let walk: WalkRecord
    /// The journal groups rows under a day heading, so its rows show the
    /// hour alone; elsewhere the row also says which day.
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
    private var date: Date { walk.endedAt ?? walk.startedAt }
    private var names: String {
        participants.map(\.dogNameSnapshot).sorted()
            .formatted(.list(type: .and).locale(TruffloLocale.french))
    }
    private var leadPhoto: Data? {
        let ids = Set(participants.map(\.dogID))
        return dogs.first { ids.contains($0.id) && $0.photoData != nil }?.photoData
    }
    private var coordinates: [TrackCoordinate] {
        // A thumbnail needs a hundred points at most.
        let stride = max(points.count / 100, 1)
        return points.enumerated().compactMap { index, point in
            index % stride == 0 || index == points.count - 1
                ? TrackCoordinate(segment: point.segment, latitude: point.latitude, longitude: point.longitude)
                : nil
        }
    }
    /// The timeline rail says GPS (solid dot) or declared (hollow ring); the
    /// words are kept for a declared walk, where they explain the ring, and
    /// when the row is shown outside the journal's day groups.
    private var origin: String {
        let how = isGPS ? "suivi GPS" : "saisie manuelle"
        if showsDay { return "\(WalkFormatting.relativeDay(date)), \(how)" }
        return isGPS ? "" : how.capitalizedFirst
    }

    var body: some View {
        TimelineRow(
            time: WalkFormatting.time(date),
            title: names.isEmpty ? "Balade" : names,
            meta: origin,
            isDeclared: !isGPS,
            figures: figures,
            note: walk.note.isEmpty ? nil : walk.note,
            photo: leadPhoto,
            route: isGPS && coordinates.count >= 2 ? coordinates : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("walk.row.\(walk.id.uuidString)")
    }

    private var figures: [String] {
        var parts = [WalkFormatting.minutes(walk.confirmedSeconds)]
        if isGPS, let meters = walk.recordedPathMeters { parts.append(WalkFormatting.distance(meters)) }
        return parts
    }

    /// The origin is spoken in words because the row shows it only in passing.
    private var spokenLabel: String {
        var parts = [names.isEmpty ? "Balade" : "Balade avec \(names)", isGPS ? "Suivi GPS" : "Saisie manuelle"]
        parts.append(WalkFormatting.dayAndTime(date))
        parts.append(contentsOf: figures)
        if !walk.note.isEmpty { parts.append(walk.note) }
        return parts.joined(separator: ", ")
    }
}

/// The shared layout of a timeline line, own walk or a member's.
struct TimelineRow: View {
    let time: String
    let title: String
    let meta: String
    /// Hollow ring on the rail instead of a solid dot: a walk the person declared.
    var isDeclared = false
    let figures: [String]
    var note: String? = nil
    var photo: Data? = nil
    var route: [TrackCoordinate]? = nil
    var flag: String? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
            if !typeSize.isAccessibilitySize {
                Text(time)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.truffloSlate)
                    .frame(width: 46, alignment: .leading)
                    .padding(.top, 3 + TruffloTheme.Spacing.small)
                rail
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.truffloForest)
                        let line = typeSize.isAccessibilitySize ? "\(time), \(meta.lowercasedFirst)" : meta
                        if !line.isEmpty {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(Color.truffloSlate)
                        }
                    }
                    Spacer(minLength: 0)
                    if let route {
                        TruffloRouteSilhouette(points: route)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else if let photo {
                        TruffloDogPortrait(name: title, photoData: photo, diameter: 44)
                    }
                }
                Text(figures.joined(separator: ", "))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.truffloCharcoal)
                if let note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloCharcoal)
                        .lineLimit(2)
                }
                if let flag {
                    Label(flag, systemImage: "square.on.square")
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                }
            }
            .padding(.vertical, TruffloTheme.Spacing.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The vertical line of the day, with a solid dot for a recorded walk and a
    /// hollow ring for a declared one. The line runs the full height of the row
    /// so consecutive rows of one day read as a single thread.
    private var rail: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.truffloForest.opacity(0.16))
                .frame(width: 2)
            Circle()
                .fill(isDeclared ? Color.truffloSand : Color.truffloForest)
                .overlay(Circle().strokeBorder(Color.truffloForest, lineWidth: isDeclared ? 2 : 0))
                .frame(width: 12, height: 12)
                .padding(.top, 5 + TruffloTheme.Spacing.small)
        }
        .frame(width: 14)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
