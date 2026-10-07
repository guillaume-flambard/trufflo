import MapKit
import SwiftData
import SwiftUI

/// Plans the next balade: a moment and, if wanted, a place found by name
/// (MapKit local search). A reminder is scheduled a little before, unless the
/// person turns it off.
struct PlanWalkSheet: View {
    let current: PlannedWalkRecord?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var query: String
    @State private var results: [MKMapItem] = []
    @State private var place: (name: String, latitude: Double, longitude: Double)?
    @State private var remind: Bool
    @State private var isSearching = false

    init(current: PlannedWalkRecord?) {
        self.current = current
        _date = State(initialValue: current?.date ?? Self.nextRoundHour())
        _query = State(initialValue: current?.placeName ?? "")
        _remind = State(initialValue: current?.remind ?? true)
        if let current, let lat = current.latitude, let lon = current.longitude {
            _place = State(initialValue: (current.placeName, lat, lon))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TruffloScreenHeader(title: "Prochaine balade",
                                        subtitle: "Choisissez un moment, et un lieu si vous voulez.")
                        .padding(.top, 4)

                    card("Quand", systemImage: "clock") {
                        DatePicker("Moment", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, TruffloLocale.french)
                            .font(.system(size: 16))
                    }

                    card("Où (facultatif)", systemImage: "mappin.and.ellipse") {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Color.truffloSlate)
                            TextField("Rechercher un lieu…", text: $query)
                                .onSubmit(search)
                                .onChange(of: query) { _, _ in search() }
                                .submitLabel(.search)
                            if place != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.truffloForest)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 46)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        if isSearching {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Recherche…").font(.footnote).foregroundStyle(Color.truffloSlate)
                            }
                            .transition(.opacity)
                        }
                        ForEach(results, id: \.self) { item in
                            Button {
                                let name = item.name ?? query
                                withAnimation(.snappy) {
                                    place = (name, item.location.coordinate.latitude, item.location.coordinate.longitude)
                                    query = name
                                    results = []
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.truffloForest)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name ?? "").font(.system(size: 15)).foregroundStyle(Color.truffloCharcoal)
                                        if let city = item.addressRepresentations?.cityName {
                                            Text(city).font(.footnote).foregroundStyle(Color.truffloSlate)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(TruffloPressStyle())
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                    card(nil, systemImage: nil) {
                        Toggle(isOn: $remind) {
                            Label("Me le rappeler 15 minutes avant", systemImage: "bell")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.truffloCharcoal)
                        }
                        .tint(Color.truffloForest)
                        .sensoryFeedback(.selection, trigger: remind)
                        Text("Une notification sur cet iPhone. Si les notifications de Trufflo sont refusées, rien ne sonne : elles se réactivent dans Réglages.")
                            .font(.footnote)
                            .foregroundStyle(Color.truffloSlate)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if current != nil {
                        Button(role: .destructive) {
                            try? JournalRepository(context: context).clearPlannedWalk()
                            WalkReminder.cancel()
                            dismiss()
                        } label: {
                            Label("Annuler cette balade prévue", systemImage: "calendar.badge.minus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.truffloDanger)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(TruffloPressStyle())
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.bottom, TruffloTheme.Spacing.large)
                .animation(.snappy, value: results.count)
                .animation(.snappy, value: isSearching)
            }
            .scrollDismissesKeyboard(.interactively)
            .truffloAura()
            .truffloScreen()
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Label("Prévoir la balade", systemImage: "calendar.badge.plus")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Color.truffloForest)
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.bottom, 8)
                .accessibilityIdentifier("plan.save")
                .truffloBottomBarFade()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer", systemImage: "xmark") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func card<Content: View>(_ title: String?, systemImage: String?,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title, let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.truffloForest)
            }
            content()
        }
        .truffloBoardCard()
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3, text != place?.name else { results = []; return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        place = nil
        Task {
            isSearching = true
            results = (try? await MKLocalSearch(request: request).start().mapItems.prefix(5)).map(Array.init) ?? []
            isSearching = false
        }
    }

    private func save() {
        let name = place?.name ?? query
        try? JournalRepository(context: context).planWalk(at: date, placeName: name,
                                                         latitude: place?.latitude, longitude: place?.longitude,
                                                         remind: remind)
        if remind {
            WalkReminder.schedule(at: date, placeName: name)
        } else {
            WalkReminder.cancel()
        }
        dismiss()
    }

    private static func nextRoundHour() -> Date {
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .hour, value: 1, to: .now)!
        return calendar.date(bySetting: .minute, value: 0, of: next) ?? next
    }
}
