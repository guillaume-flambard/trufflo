import SwiftUI
import SwiftData

/// One recorded walk, read in full (PRD F05), with a targeted delete.
///
/// An absent distance is written "Non mesurée", never "0": a missing measurement
/// and a measured zero are different facts and the UI must not merge them.
@MainActor
struct WalkDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var matches: [WalkRecord]
    @Query private var participants: [WalkDogRecord]
    @Query private var points: [TrackPointRecord]
    @Query(sort: \DogRecord.createdAt) private var dogs: [DogRecord]
    @Query private var photos: [WalkPhotoRecord]
    @State private var showEditor = false

    @State private var showDeleteConfirmation = false
    @State private var routeFile: SharedFile?
    @State private var showCorrection = false
    @State private var storageError: String?
    /// A finished walk is framed once and never chases the camera afterwards.
    @State private var isFollowingTrack = false

    init(walkID: UUID) {
        _matches = Query(filter: #Predicate<WalkRecord> { $0.id == walkID })
        _participants = Query(filter: #Predicate<WalkDogRecord> { $0.walkID == walkID })
        _points = Query(filter: #Predicate<TrackPointRecord> { $0.walkID == walkID },
                        sort: \.sequence, order: .forward)
        _photos = Query(filter: #Predicate<WalkPhotoRecord> { $0.walkID == walkID },
                        sort: \.createdAt)
    }

    var body: some View {
        Group {
            if let walk = matches.first {
                content(for: walk)
            } else {
                TruffloNotice(title: "Cette balade n'existe plus", message: "Elle a été retirée de cet iPhone depuis un autre écran.", actionTitle: "Revenir au journal") { dismiss() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .truffloScreen()
        .alert("Modification impossible", isPresented: Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )) {
            Button("Fermer", role: .cancel) {}
        } message: {
            Text(storageError ?? "")
        }
    }

    /// The walk read in full, laid out on the 2026-10-07 mock-up: the tracé across
    /// the top, then a sand sheet rising over it with who and when, the figures in
    /// one tinted block, the note, the facts of the measure, and the actions.
    @ViewBuilder
    private func content(for walk: WalkRecord) -> some View {
        let shown = WalkPresentation(walk: walk, participants: participants, dogs: dogs, points: points)
        let trackCoordinates = shown.route() ?? []
        let hasMap = !trackCoordinates.isEmpty
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hasMap {
                    TruffloTrackMap(points: trackCoordinates,
                                    isLive: false,
                                    showsMarkers: false,
                                    isFollowing: $isFollowingTrack)
                        .frame(height: 240)
                        .accessibilityIdentifier("walk.detail.map")
                }

                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                    if hasMap {
                        Capsule().fill(Color.black.opacity(0.15)).frame(width: 40, height: 5)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                    header(walk, shown)
                    statsBlock(walk, shown)
                    photosSection(walk)
                    noteCard(walk)
                    if walk.weather != nil || walk.temperatureC != nil { environmentCard(walk) }
                    measureCard(walk)
                    actionsCard(walk, hasMap: hasMap)
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.top, hasMap ? 10 : 60)
                .padding(.bottom, TruffloTheme.Spacing.xLarge)
                .background(hasMap ? Color.truffloSand : Color.clear,
                            in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
                .padding(.top, hasMap ? -28 : 0)
            }
        }
        .toolbar {
            if hasMap {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Exporter le tracé", systemImage: "square.and.arrow.up") { exportRoute(of: walk) }
                }
            }
        }
        // The route runs under the bar, edge to edge; the back button floats in glass.
        .ignoresSafeArea(edges: hasMap ? .top : [])
        // A walk declared by hand has no route to open on: the page takes the same
        // mint aura as the dog's screens instead of a bare sand head.
        .background(alignment: .top) {
            if !hasMap {
                TruffloDogAura(photoData: nil)
                    .frame(height: 360)
                    .ignoresSafeArea(edges: .top)
            }
        }
        // The bar never draws a title or a band: the dogs' names below are the
        // title, as on the profile, so both kinds of walk open the same way.
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .navigationTitle("")
        .task(id: walk.id) {
            // The place is looked up once, then kept: older balades get theirs too.
            guard walk.source != .manual, walk.placeName.isEmpty, trackCoordinates.count >= 2 else { return }
            if let name = await WalkPlaceResolver.placeName(for: trackCoordinates) {
                try? JournalRepository(context: context).setWalkSurroundings(walk.id, placeName: name,
                                                                             weather: nil, temperatureC: nil)
            }
        }
        .sheet(isPresented: $showEditor) {
            WalkDetailsEditor(walk: walk)
        }
        .sheet(isPresented: $showCorrection) {
            WalkCorrectionView(walk: walk, participants: participants,
                               existingDogIDs: Set(dogs.map(\.id)))
        }
        .sheet(item: $routeFile) { file in
            ShareSheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Supprimer cette balade ?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) { delete(walkID: walk.id) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La balade, ses participants et ses points enregistrés seront retirés de cet appareil.")
        }
    }

    // MARK: - Pieces

    private func header(_ walk: WalkRecord, _ shown: WalkPresentation) -> some View {
        HStack(alignment: .top, spacing: TruffloTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                // The dogs are the title; the hour is a fact, not a name.
                Text(shown.title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.truffloForest)
                    .fixedSize(horizontal: false, vertical: true)
                Text(WalkFormatting.relativeDayAndTime(shown.date).capitalizedFirst)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.truffloSlate)
                if !walk.placeName.isEmpty {
                    Label(walk.placeName, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.truffloSlate)
                        .accessibilityIdentifier("walk.detail.place")
                }
                if shown.names.isEmpty {
                    Text("Aucun chien associé à cette balade.")
                        .font(.subheadline)
                        .foregroundStyle(Color.truffloSlate)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: TruffloTheme.Spacing.small) {
                // A face only when there is a photo: no initial on a disc.
                if let photo = shown.leadPhoto {
                    TruffloDogPortrait(name: shown.leadName ?? "", photoData: photo, diameter: 56, aimsAtAnimal: true)
                }
                Label(walk.mood?.label ?? (shown.isTracked ? "Balade suivie" : "Balade ajoutée"),
                      systemImage: walk.mood?.systemImage ?? "figure.walk")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.truffloForest)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.86, green: 0.93, blue: 0.89), in: Capsule())
            }
        }
    }

    /// The figures in one tinted block: duration, and for a balade suivie the
    /// distance and the average speed it implies. Never a calorie or a target.
    private func statsBlock(_ walk: WalkRecord, _ shown: WalkPresentation) -> some View {
        var items: [(icon: String, value: String, label: String)] = [
            ("clock", WalkFormatting.minutes(walk.confirmedSeconds), "Durée"),
        ]
        if shown.isTracked, let meters = walk.recordedPathMeters {
            items.append(("point.topleft.down.to.point.bottomright.curvepath", WalkFormatting.distance(meters), "Distance"))
            if walk.confirmedSeconds >= 60 {
                let kmh = (meters / 1000) / (walk.confirmedSeconds / 3600)
                let text = kmh.formatted(.number.precision(.fractionLength(1)).locale(TruffloLocale.french))
                items.append(("gauge.with.needle", "\(text) km/h", "Allure moyenne"))
            }
        }
        let lead = dogs.first { dog in participants.contains { $0.dogID == dog.id } }
        if shown.isTracked, let kcal = CalorieEstimate.kcal(weightKg: lead?.weightKg,
                                                            meters: walk.recordedPathMeters, size: lead?.size) {
            items.append(("flame", "\(kcal) kcal", "Estimation"))
        }
        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(Color.truffloForest.opacity(0.12)).frame(width: 1, height: 48)
                }
                VStack(spacing: 4) {
                    Image(systemName: item.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.truffloForest)
                    Text(item.value)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.truffloForest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.truffloSlate)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, TruffloTheme.Spacing.small)
        .background(Color(red: 0.91, green: 0.95, blue: 0.92),
                    in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
    }

    private func noteCard(_ walk: WalkRecord) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            HStack {
                Label("Note", systemImage: "note.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.truffloSlate)
                Spacer()
                if walk.phase == .completed {
                    Button("Modifier") { showEditor = true }
                        .accessibilityIdentifier("walk.details.edit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.truffloForest)
                }
            }
            Text(walk.note.isEmpty ? "Aucune note pour cette balade." : walk.note)
                .font(.system(size: 13))
                .foregroundStyle(walk.note.isEmpty ? Color.truffloSlate : Color.truffloCharcoal)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
    }

    /// The photos of the balade, a row of four with the rest counted on the last
    /// one; an invitation to add some when there are none.
    @ViewBuilder
    private func photosSection(_ walk: WalkRecord) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            HStack {
                Text("Photos")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.truffloForest)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if photos.count > 4 {
                    Button { showEditor = true } label: {
                        HStack(spacing: 4) { Text("Voir tout (\(photos.count))"); Image(systemName: "chevron.right").imageScale(.small) }
                            .font(.system(size: 13))
                            .foregroundStyle(Color.truffloSlate)
                    }
                    .buttonStyle(.plain)
                }
            }
            if photos.isEmpty {
                Button { showEditor = true } label: {
                    Label("Ajouter des photos", systemImage: "photo.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.truffloForest)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.white.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.truffloForest.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("walk.photos.add")
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(photos.prefix(4).enumerated()), id: \.element.id) { index, photo in
                        let isLast = index == 3 && photos.count > 4
                        TruffloDogThumbnail(name: "", photoData: photo.data, side: 80,
                                            width: index == 0 ? 100 : nil, bordered: false)
                            .overlay {
                                if isLast {
                                    RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous)
                                        .fill(.black.opacity(0.35))
                                    Text("+\(photos.count - 3)").font(.title3.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(photos.count) photos")
            }
        }
    }

    /// The weather at the end of the balade, when the service answered.
    private func environmentCard(_ walk: WalkRecord) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            Label("Environnement", systemImage: "leaf")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.truffloSlate)
            HStack(spacing: 8) {
                if let weather = walk.weather {
                    Label(weather.label, systemImage: weather.systemImage)
                        .symbolRenderingMode(.multicolor)
                }
                if let temperature = walk.temperatureC {
                    Label("\(Int(temperature.rounded())) °C", systemImage: "thermometer.medium")
                        .symbolRenderingMode(.multicolor)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.truffloCharcoal)
            .labelStyle(EnvironmentChipStyle())
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
    }

    /// How the balade was measured, where the mock-up shows its surroundings: the
    /// app knows the measure, not the weather.
    private func measureCard(_ walk: WalkRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Mesure", systemImage: "location")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.truffloSlate)
                .padding(.bottom, 4)
            WalkFactRow("Mesure", WalkFormatting.quality(walk.quality))
            if walk.recordedPathMeters == nil {
                WalkFactRow("Distance", "Non mesurée")
            }
            if walk.source != .manual, let endedAt = walk.endedAt {
                WalkFactRow("Départ et retour", WalkFormatting.timeRange(walk.startedAt, endedAt))
            } else {
                WalkFactRow("Fin de la balade", walk.endedAt.map(WalkFormatting.relativeDayAndTime) ?? "En cours")
            }
            if let correctedAt = walk.correctedAt {
                WalkFactRow("Corrigée", WalkFormatting.relativeDayAndTime(correctedAt))
            }
        }
        .padding(TruffloTheme.Spacing.medium)
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
    }

    private func actionsCard(_ walk: WalkRecord, hasMap: Bool) -> some View {
        VStack(spacing: 0) {
            if walk.phase == .completed {
                actionRow("Corriger la balade", icon: "pencil", identifier: "walk.correct") { showCorrection = true }
                Divider().padding(.leading, 52)
            }
            if hasMap {
                actionRow("Exporter le tracé (GPX)", icon: "square.and.arrow.up", identifier: "walk.export.gpx") {
                    exportRoute(of: walk)
                }
                Divider().padding(.leading, 52)
            }
            actionRow("Supprimer la balade", icon: "trash", identifier: "walk.delete", isDestructive: true) {
                showDeleteConfirmation = true
            }
            .accessibilityLabel(accessibilityDeleteLabel(for: walk))
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
    }

    private func actionRow(_ title: String, icon: String, identifier: String, isDestructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: TruffloTheme.Spacing.medium) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 22)
                    .foregroundStyle(isDestructive ? Color.truffloDanger : Color.truffloForest)
                Text(title).font(.system(size: 14))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.truffloSlate)
            }
            .foregroundStyle(isDestructive ? Color.truffloDanger : Color.truffloCharcoal)
            .padding(.horizontal, TruffloTheme.Spacing.medium)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .truffloTap()
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Formatting

    private func accessibilityDeleteLabel(for walk: WalkRecord) -> String {
        guard let endedAt = walk.endedAt else { return "Supprimer la balade en cours" }
        let date = endedAt.formatted(.dateTime.day().month())
        return "Supprimer la balade du \(date)"
    }

    /// One walk's route as a GPX file. Read back from the export path, so the
    /// file is the same one the full journal export would contain.
    private func exportRoute(of walk: WalkRecord) {
        do {
            guard let exported = try JournalRepository(context: context).exportWalks()
                    .first(where: { $0.id == walk.id }),
                  let gpx = WalkExport.gpx(exported) else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(WalkExport.gpxFileName(for: exported))
            try Data(gpx.utf8).write(to: url, options: .atomic)
            routeFile = SharedFile(url: url)
        } catch {
            storageError = "Le tracé n'a pas pu être exporté."
        }
    }

    private func delete(walkID: UUID) {
        do {
            try JournalRepository(context: context).deleteWalk(walkID)
            dismiss()
        } catch JournalError.walkMissing {
            storageError = "Cette balade n'existe plus."
        } catch {
            storageError = "La balade n'a pas été supprimée. Les données précédentes ont été conservées."
        }
    }
}

/// A section heading in the walk screens, the same everywhere.
struct WalkSectionTitle: View {
    private let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(Color.truffloForest)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One fact about a walk: a label and its value on one line, separated by a
/// hairline from the next. The value wraps under the label at large sizes.
struct WalkFactRow: View {
    private let label: String
    private let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(Color.truffloSlate)
                Spacer(minLength: TruffloTheme.Spacing.small)
                Text(value).foregroundStyle(Color.truffloCharcoal).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(Color.truffloSlate)
                Text(value).foregroundStyle(Color.truffloCharcoal)
            }
        }
        .font(.system(size: 13))
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.truffloForest.opacity(0.1)).frame(height: 1)
        }
    }
}

private struct EnvironmentChipStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon; configuration.title }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Color.black.opacity(0.04), in: Capsule())
    }
}
