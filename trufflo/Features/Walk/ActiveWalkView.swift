import SwiftUI
import SwiftData

@MainActor
public struct ActiveWalkView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ActiveWalkViewModel
    @Query private var dogs: [DogRecord]
    @State private var showFinishConfirmation = false
    @State private var showManualCorrection = false
    /// Presentation mirror of `viewModel.startBlock`. The model stays the source
    /// of truth for *what* blocked the start; the alert owns only its own
    /// visibility. Writing back to the model from the dismissal closure would
    /// publish during a view update, which SwiftUI reports as undefined
    /// behaviour (same class as E-026).
    @State private var blockedAlert: LocationBlock?
    private let dogIDsToStart: [UUID]
    private let walkIDToResume: UUID?

    public init(modelContainer: ModelContainer, dogIDs: [UUID] = []) {
        _viewModel = StateObject(wrappedValue: ActiveWalkViewModel(modelContainer: modelContainer))
        dogIDsToStart = dogIDs
        walkIDToResume = nil
    }

    public init(modelContainer: ModelContainer, existingWalkID: UUID) {
        _viewModel = StateObject(wrappedValue: ActiveWalkViewModel(modelContainer: modelContainer))
        dogIDsToStart = []
        walkIDToResume = existingWalkID
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: TruffloTheme.Spacing.large) {
                // MARK: - Participants & Status Header
                HStack {
                    HStack(spacing: TruffloTheme.Spacing.xSmall) {
                        ForEach(viewModel.dogNames, id: \.self) { name in
                            TruffloBadge(name, icon: "pawprint.fill", style: .sage)
                        }
                    }
                    Spacer()
                    TruffloBadge(
                        viewModel.phase == .recording ? "En cours"
                            : viewModel.phase == .interrupted ? "Interrompue" : "En pause",
                        icon: viewModel.phase == .recording ? "record.circle.fill"
                            : viewModel.phase == .interrupted ? "exclamationmark.triangle.fill" : "pause.circle.fill",
                        style: viewModel.phase == .recording ? .peach : .sand
                    )
                    .accessibilityIdentifier("walk.phase.badge")
                }
                .padding(.horizontal, TruffloTheme.Spacing.medium)

                // MARK: - Live Stats Card
                TruffloCard(variant: .sand) {
                    VStack(spacing: TruffloTheme.Spacing.medium) {
                        VStack(spacing: TruffloTheme.Spacing.xxSmall) {
                            Text("DURÉE MONTRÉE")
                                .font(.truffloCaption)
                                .foregroundStyle(Color.truffloCharcoal.opacity(0.6))
                            Text(formatDuration(viewModel.confirmedSeconds))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.truffloForest)
                                .accessibilityIdentifier("walk.timer")
                                .accessibilityAddTraits(.updatesFrequently)
                        }

                        Divider()

                        HStack(spacing: TruffloTheme.Spacing.large) {
                            VStack(spacing: 4) {
                                Text("DISTANCE")
                                    .font(.truffloCaption)
                                    .foregroundStyle(Color.truffloCharcoal.opacity(0.6))
                                Text(formatDistance(viewModel.distanceMeters))
                                    .font(.truffloHeadline)
                                    .foregroundStyle(Color.truffloForest)
                                    .accessibilityIdentifier("walk.distance")
                                    .accessibilityAddTraits(.updatesFrequently)
                            }
                            .frame(maxWidth: .infinity)

                            Divider().frame(height: 36)

                            VStack(spacing: 4) {
                                Text("SIGNAL GPS")
                                    .font(.truffloCaption)
                                    .foregroundStyle(Color.truffloCharcoal.opacity(0.6))
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(viewModel.isLocationActive ? Color.green
                                              : viewModel.phase == .interrupted ? Color.gray : Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text(viewModel.isLocationActive ? "Actif"
                                         : viewModel.phase == .interrupted ? "Arrêté" : "Recherche")
                                        .font(.truffloSubheadline)
                                        .foregroundStyle(Color.truffloCharcoal)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, TruffloTheme.Spacing.small)
                }
                .padding(.horizontal, TruffloTheme.Spacing.medium)

                // MARK: - Note Input Card
                TruffloCard(variant: .plain) {
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                        Text("Note de balade (facultative)")
                            .font(.truffloCaption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.truffloForest)

                        TextField("Observation, comportement...", text: $viewModel.note, axis: .vertical)
                            .font(.truffloBody)
                            .lineLimit(2...4)
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.medium)

                Spacer()

                // MARK: - Control Buttons
                VStack(spacing: TruffloTheme.Spacing.medium) {
                    if viewModel.phase == .interrupted {
                        Text("Cette balade s'est interrompue. Les données enregistrées jusqu'au dernier point sont conservées.")
                            .font(.truffloCaption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, TruffloTheme.Spacing.medium)

                        // Only a withdrawn permission can be repaired from
                        // here. A restriction or a disabled service would send
                        // the user to a Settings page that cannot help.
                        if viewModel.interruptionBlock?.offersSettings == true {
                            Button("Ouvrir les réglages") {
                                viewModel.openSettings()
                            }
                            .buttonStyle(.truffloOutline)
                            .accessibilityIdentifier("walk.interrupted.settings")
                        }

                        Button("Reprendre à partir de maintenant") {
                            viewModel.resume()
                        }
                        .buttonStyle(.truffloPrimary)
                        .accessibilityIdentifier("walk.recover.resume")

                        Button("Terminer avec les données enregistrées") {
                            Task {
                                await viewModel.finish()
                                dismiss()
                            }
                        }
                        .buttonStyle(.truffloOutline)
                        .accessibilityIdentifier("walk.recover.finish")

                        Button("Corriger") {
                            showManualCorrection = true
                        }
                        .buttonStyle(.truffloSecondary)
                        .accessibilityIdentifier("walk.recover.correct")
                    } else if viewModel.phase == .recording {
                        Button("Mettre en pause") {
                            viewModel.pause()
                        }
                        .buttonStyle(.truffloSecondary)

                        Button("Terminer la balade") {
                            showFinishConfirmation = true
                        }
                        .buttonStyle(.truffloOutline)
                        .accessibilityIdentifier("walk.finish")
                    } else {
                        Button("Reprendre la balade") {
                            viewModel.resume()
                        }
                        .buttonStyle(.truffloPrimary)

                        Button("Terminer la balade") {
                            showFinishConfirmation = true
                        }
                        .buttonStyle(.truffloOutline)
                        .accessibilityIdentifier("walk.finish")
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.medium)
                .padding(.bottom, TruffloTheme.Spacing.large)
            }
            .navigationTitle("Balade en direct")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .task {
                if let walkIDToResume {
                    viewModel.resumeExisting(walkID: walkIDToResume)
                } else if !dogIDsToStart.isEmpty {
                    viewModel.startSession(dogIDs: dogIDsToStart)
                }
            }
            .onChange(of: viewModel.startBlock) { _, block in
                blockedAlert = block
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                    .font(.truffloSubheadline)
                }
            }
            .sheet(isPresented: $showManualCorrection) {
                ManualWalkFormView(dogs: dogs)
            }
            .confirmationDialog(
                "Terminer et enregistrer la balade ?",
                isPresented: $showFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Terminer la balade", role: .none) {
                    Task {
                        await viewModel.finish()
                        dismiss()
                    }
                }
                Button("Continuer") {}
            } message: {
                Text("La durée et le tracé GPS de votre sortie seront ajoutés à votre journal.")
            }
            .alert("Erreur", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            // A refused start is not an error string: the spec asks for the
            // reason, a route into Settings when that can actually fix it, and
            // manual entry either way, so a walk stays possible without GPS.
            .alert(
                blockedAlert?.message ?? "",
                isPresented: Binding(
                    get: { blockedAlert != nil },
                    set: { if !$0 { blockedAlert = nil } }
                )
            ) {
                if blockedAlert?.offersSettings == true {
                    Button("Ouvrir les réglages") {
                        viewModel.openSettings()
                        clearBlockedAlert()
                    }
                    .accessibilityIdentifier("walk.blocked.settings")
                    Button("Ajouter manuellement") {
                        clearBlockedAlert()
                        showManualCorrection = true
                    }
                    .accessibilityIdentifier("walk.blocked.manual")
                    Button("Annuler") { clearBlockedAlert() }
                } else {
                    Button("Ajouter manuellement") {
                        clearBlockedAlert()
                        showManualCorrection = true
                    }
                    .accessibilityIdentifier("walk.blocked.manual")
                    Button("OK") { clearBlockedAlert() }
                }
            }
        }
    }

    private func clearBlockedAlert() {
        blockedAlert = nil
        viewModel.dismissStartBlock()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hrs > 0 {
            return String(format: "%02d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    private func formatDistance(_ meters: Double?) -> String {
        guard let meters else { return "Non mesurée" }
        if meters >= 1000 {
            let km = meters / 1000.0
            return String(format: "%.2f km", km)
        }
        return String(format: "%.0f m", meters)
    }
}
