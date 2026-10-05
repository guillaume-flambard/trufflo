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

    @State private var showDeleteConfirmation = false
    @State private var storageError: String?

    init(walkID: UUID) {
        _matches = Query(filter: #Predicate<WalkRecord> { $0.id == walkID })
        _participants = Query(filter: #Predicate<WalkDogRecord> { $0.walkID == walkID })
    }

    var body: some View {
        Group {
            if let walk = matches.first {
                content(for: walk)
            } else {
                TruffloEmptyStateView(
                    imageName: "EmptyWalk",
                    title: "Cette balade n'existe plus",
                    description: "Elle a été retirée de cet appareil."
                )
            }
        }
        .navigationTitle("Balade")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.truffloForest)
        .alert("Modification impossible", isPresented: Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )) {
            Button("Fermer", role: .cancel) {}
        } message: {
            Text(storageError ?? "")
        }
    }

    @ViewBuilder
    private func content(for walk: WalkRecord) -> some View {
        List {
            Section("Chiens") {
                let names = participants.map(\.dogNameSnapshot).sorted()
                if names.isEmpty {
                    Text("Aucun chien associé à cette balade.")
                        .font(.truffloBody)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: TruffloTheme.Spacing.xSmall) {
                        ForEach(names, id: \.self) { name in
                            TruffloBadge(name, icon: "pawprint.fill", style: .sage)
                        }
                    }
                }
            }

            Section("Mesures") {
                LabeledContent("Fin de la balade") {
                    if let endedAt = walk.endedAt {
                        Text(endedAt, format: .dateTime.day().month().hour().minute())
                            .font(.truffloSubheadline)
                    } else {
                        TruffloBadge("En cours", icon: "record.circle", style: .peach)
                    }
                }
                LabeledContent("Durée") {
                    Text(durationText(walk.confirmedSeconds))
                        .font(.truffloHeadline)
                        .foregroundStyle(Color.truffloForest)
                }
                LabeledContent("Origine") {
                    TruffloBadge(walk.source == .manual ? "Saisie manuelle" : "Suivi GPS",
                                 icon: walk.source == .manual ? "square.and.pencil" : "location.fill",
                                 style: walk.source == .manual ? .sand : .peach)
                }
                LabeledContent("Qualité") {
                    Text(qualityText(walk.quality))
                        .font(.truffloSubheadline)
                }
                LabeledContent("Distance") {
                    if let meters = walk.recordedPathMeters {
                        Text(distanceText(meters))
                            .font(.truffloHeadline)
                            .foregroundStyle(Color.truffloForest)
                    } else {
                        Text("Non mesurée")
                            .font(.truffloSubheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !walk.note.isEmpty {
                Section("Note") {
                    Text(walk.note)
                        .font(.truffloBody)
                        .foregroundStyle(Color.truffloCharcoal)
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Supprimer la balade", systemImage: "trash")
                        .font(.truffloSubheadline)
                }
                .accessibilityIdentifier("walk.delete")
                .accessibilityLabel(accessibilityDeleteLabel(for: walk))
            } footer: {
                Text("La balade, les chiens qui y figurent et les points enregistrés sont retirés de cet appareil.")
                    .font(.truffloCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Supprimer cette balade ?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) { delete(walkID: walk.id) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La balade, ses participants et ses points enregistrés seront retirés de cet appareil.")
        }
    }

    // MARK: - Formatting

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = (seconds / 60).formatted(.number.precision(.fractionLength(0...1)))
        return "\(minutes) min"
    }

    private func distanceText(_ meters: Double) -> String {
        if meters >= 1000 {
            let kilometers = (meters / 1000).formatted(.number.precision(.fractionLength(1...2)))
            return "\(kilometers) km"
        }
        let rounded = meters.formatted(.number.precision(.fractionLength(0)))
        return "\(rounded) m"
    }

    private func qualityText(_ quality: WalkQuality) -> String {
        switch quality {
        case .gpsRecorded: "Mesurée par GPS"
        case .gpsPartial: "Mesure partielle"
        case .manual: "Déclarée à la main"
        case .unavailable: "Non mesurée"
        }
    }

    private func accessibilityDeleteLabel(for walk: WalkRecord) -> String {
        guard let endedAt = walk.endedAt else { return "Supprimer la balade en cours" }
        let date = endedAt.formatted(.dateTime.day().month())
        return "Supprimer la balade du \(date)"
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
