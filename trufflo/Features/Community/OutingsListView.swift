import SwiftUI

/// The zone's coming outings, and this person's own. Days as headings, one line
/// per outing, no card: the same language as the journal.
struct OutingsListView: View {
    @Environment(CommunityModel.self) private var model
    @Environment(\.calendar) private var calendar
    @State private var tab = "upcoming"
    @State private var showEditor = false
    @State private var showBlocked = false

    private var shown: [OutingDTO] { tab == "upcoming" ? model.outings : model.myOutings }

    private var days: [(start: Date, outings: [OutingDTO])] {
        let grouped = Dictionary(grouping: shown) { calendar.startOfDay(for: $0.startsAt) }
        let upcoming = tab == "upcoming"
        let starts = grouped.keys.sorted { upcoming ? $0 < $1 : $0 > $1 }
        return starts.map { ($0, grouped[$0]!.sorted { $0.startsAt < $1.startsAt }) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                    Text("Sorties")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.truffloForest)
                    if let zone = model.zoneName {
                        Text(zone).font(.subheadline).foregroundStyle(Color.truffloSlate)
                    }
                }

                TruffloChoice(options: [("upcoming", "À venir"), ("mine", "Mes sorties")], selection: $tab)
                CommunityErrorLine()

                if shown.isEmpty {
                    emptyState
                } else {
                    ForEach(days, id: \.start) { day in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(OutingFormatting.day(day.start))
                                .font(.system(.title2, design: .rounded, weight: .heavy))
                                .foregroundStyle(Color.truffloForest)
                                .padding(.bottom, TruffloTheme.Spacing.xxSmall)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(day.outings) { outing in
                                NavigationLink(value: OutingRoute(id: outing.id)) {
                                    OutingRow(outing: outing, isMine: outing.organizerID == model.userID)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("outing.row.\(outing.id.uuidString)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.vertical, TruffloTheme.Spacing.medium)
        }
        .refreshable { await model.refresh() }
        .toolbar {
            if model.isOrganizer {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Proposer une sortie", systemImage: "plus") { showEditor = true }
                        .accessibilityIdentifier("outing.create")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu("Réglages des sorties", systemImage: "ellipsis.circle") {
                    Button("Personnes bloquées", systemImage: "hand.raised") { showBlocked = true }
                    if let contact = CommunityContact.url {
                        Link(destination: contact) { Label("Contacter l'équipe", systemImage: "envelope") }
                    }
                }
                .accessibilityIdentifier("community.menu")
            }
        }
        .navigationDestination(isPresented: $showBlocked) { BlockedPeopleView() }
        .sheet(isPresented: $showEditor) { OutingEditorView(mode: .create(prefill: nil)) }
        // The page names itself in large type: a bar title would say it twice.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            if tab == "upcoming" {
                Text("Aucune sortie à venir dans \(model.zoneName ?? "votre zone")")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.truffloForest)
                Text("Quand un organisateur de votre zone en proposera une, elle apparaîtra ici. Rien n'est affiché tant qu'il n'y en a pas.")
                    .font(.subheadline)
                    .foregroundStyle(Color.truffloSlate)
            } else {
                Text("Vous n'avez pas encore de sortie")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.truffloForest)
                Text("Vos demandes, vos sorties confirmées et celles que vous organisez seront ici.")
                    .font(.subheadline)
                    .foregroundStyle(Color.truffloSlate)
            }
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
            .strokeBorder(Color.truffloForest.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .accessibilityIdentifier("community.empty")
    }
}

/// One outing as a line: the hour in the margin, the meeting point as the title.
private struct OutingRow: View {
    let outing: OutingDTO
    let isMine: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: TruffloTheme.Spacing.medium) {
            if !typeSize.isAccessibilitySize {
                Text(outing.startsAt.formatted(.dateTime.hour().minute().locale(TruffloLocale.french)))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.truffloSlate)
                    .frame(width: 46, alignment: .leading)
                    .padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(outing.meetingPoint)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.truffloForest)
                Text("\(typeSize.isAccessibilitySize ? OutingFormatting.timeRange(outing) + ", " : "")\(outing.organizerName) organise, \(OutingFormatting.duration(outing.durationMinutes))")
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
                Text(OutingFormatting.places(outing))
                    .font(.subheadline)
                    .foregroundStyle(Color.truffloCharcoal)
                if let status = OutingFormatting.myStatus(outing, organizerIsMe: isMine) {
                    Label(status, systemImage: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(outing.status == .cancelled ? Color.truffloDanger : Color.truffloForest)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, TruffloTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        if outing.status == .cancelled { return "xmark.circle" }
        if isMine { return "megaphone" }
        switch outing.myStatus {
        case .accepted: return "checkmark.circle"
        case .requested: return "hourglass"
        default: return "circle"
        }
    }
}
