import SwiftUI

/// The zone's coming outings, and this person's own. Days as headings, one
/// card per outing: the same language as the journal.
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
            LazyVStack(alignment: .leading, spacing: 14) {
                TruffloScreenHeader(
                    title: "Sorties",
                    subtitle: model.zoneName.map { "Balades à plusieurs, \($0)." },
                    action: model.isOrganizer
                        ? .init(systemImage: "plus", label: "Proposer une sortie",
                                identifier: "outing.create") { showEditor = true }
                        : nil)

                TruffloFilterChips(options: [("upcoming", "À venir"), ("mine", "Mes sorties")], selection: $tab)
                CommunityErrorLine()

                if shown.isEmpty {
                    emptyState
                } else {
                    ForEach(days, id: \.start) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            TruffloSectionTitle(OutingFormatting.day(day.start))
                            ForEach(day.outings) { outing in
                                NavigationLink(value: OutingRoute(id: outing.id)) {
                                    OutingRow(outing: outing, isMine: outing.organizerID == model.userID)
                                }
                                .buttonStyle(TruffloPressStyle())
                                .accessibilityIdentifier("outing.row.\(outing.id.uuidString)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.bottom, TruffloTheme.Spacing.medium)
            .animation(.snappy, value: tab)
        }
        .refreshable { await model.refresh() }
        .truffloAura()
        .toolbar {
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
        .truffloBoardCard()
        .accessibilityIdentifier("community.empty")
    }
}

/// One outing as a line: the hour in the margin, the meeting point as the title.
private struct OutingRow: View {
    let outing: OutingDTO
    let isMine: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if !typeSize.isAccessibilitySize {
                // The hour as a small block, like a calendar entry.
                Text(outing.startsAt.formatted(.dateTime.hour().minute().locale(TruffloLocale.french)))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.truffloForest)
                    .frame(width: 58, height: 44)
                    .background(Color(red: 0.89, green: 0.94, blue: 0.90),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(outing.meetingPoint)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
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
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.truffloSlate.opacity(0.6))
                .padding(.top, 4)
        }
        .truffloBoardCard(padding: 12)
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
