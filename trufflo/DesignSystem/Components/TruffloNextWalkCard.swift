import SwiftData
import SwiftUI

/// "Prochaine balade" (2026-10-07 board): the planned moment and place, and the
/// one button that starts a balade. Without a plan, an invitation to set one.
struct TruffloNextWalkCard<StartButton: View>: View {
    let plan: PlannedWalkRecord?
    let onPlan: () -> Void
    @ViewBuilder var startButton: () -> StartButton

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onPlan) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Prochaine balade")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                        if let plan {
                            Label(WalkFormatting.dayDotTime(plan.date),
                                  systemImage: "clock")
                            if !plan.placeName.isEmpty {
                                Label(plan.placeName, systemImage: "mappin.circle").lineLimit(1)
                            }
                        } else {
                            Label("Pas encore prévue : choisir un moment", systemImage: "calendar.badge.plus")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.truffloSlate)
                    Spacer(minLength: 0)
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.truffloForest)
                        .padding(.top, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.plan")
            startButton()
        }
        .padding(16)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, y: 5)
    }
}

/// The last balade on Accueil, as on the board: when, its name, its figures, and
/// its picture on the right (a photo of the balade, else the dog's).
struct TruffloLastWalkRow: View {
    let walk: WalkRecord

    @Query private var participants: [WalkDogRecord]
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]
    @Query private var photos: [WalkPhotoRecord]

    init(walk: WalkRecord) {
        self.walk = walk
        let walkID = walk.id
        _participants = Query(filter: #Predicate<WalkDogRecord> { $0.walkID == walkID })
        _photos = Query(filter: #Predicate<WalkPhotoRecord> { $0.walkID == walkID }, sort: \.createdAt)
    }

    var body: some View {
        let shown = WalkPresentation(walk: walk, participants: participants, dogs: dogs, points: [])
        var figures = [WalkFormatting.minutes(walk.confirmedSeconds)]
        if let meters = walk.recordedPathMeters { figures.append(WalkFormatting.distance(meters)) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Label(WalkFormatting.dayDotTime(shown.date),
                      systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.truffloSlate)
                Text(shown.heading)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                    .lineLimit(1)
                Text(figures.joined(separator: " · "))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.truffloForest)
            }
            Spacer(minLength: 0)
            if let photo = photos.first?.data ?? shown.leadPhoto {
                TruffloDogThumbnail(name: shown.leadName ?? "", photoData: photo, side: 76, width: 96, bordered: false)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.lastWalk")
    }
}
