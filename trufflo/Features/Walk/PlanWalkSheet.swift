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
            Form {
                Section("Quand") {
                    DatePicker("Moment", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, TruffloLocale.french)
                }
                Section("Où (facultatif)") {
                    TextField("Rechercher un lieu…", text: $query)
                        .onSubmit(search)
                        .onChange(of: query) { _, _ in search() }
                    ForEach(results, id: \.self) { item in
                        Button {
                            let name = item.name ?? query
                            place = (name, item.location.coordinate.latitude, item.location.coordinate.longitude)
                            query = name
                            results = []
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? "").foregroundStyle(Color.truffloCharcoal)
                                if let city = item.addressRepresentations?.cityName {
                                    Text(city).font(.footnote).foregroundStyle(Color.truffloSlate)
                                }
                            }
                        }
                    }
                }
                Section {
                    Toggle("Me le rappeler 15 minutes avant", isOn: $remind)
                } footer: {
                    Text("Une notification sur cet iPhone. Si les notifications de Trufflo sont refusées, rien ne sonne : elles se réactivent dans Réglages.")
                }
                if current != nil {
                    Section {
                        Button("Annuler cette balade prévue", role: .destructive) {
                            try? JournalRepository(context: context).clearPlannedWalk()
                            WalkReminder.cancel()
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationTitle("Prochaine balade")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Prévoir", action: save).fontWeight(.semibold)
                }
            }
        }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3, text != place?.name else { results = []; return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        Task {
            results = (try? await MKLocalSearch(request: request).start().mapItems.prefix(5)).map(Array.init) ?? []
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
