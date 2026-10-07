import SwiftUI
import UserNotifications

/// Réglages, as a sheet built from the board's pieces: the screen head, white
/// cards of rows, one destructive row per card at most, said in plain words.
/// Everything that ends something asks first, here, over the sheet.
struct SettingsView: View {
    let hasSharedData: Bool
    let onOpenFoyer: () -> Void
    let onExport: () -> Void
    let onShowIntroduction: () -> Void
    let onErase: () -> Void

    @Environment(HouseholdModel.self) private var household
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmErase = false
    @State private var confirmDeleteAccount = false
    @State private var deletingAccount = false
    @State private var accountResult: AccountResult?
    @State private var notifications: UNAuthorizationStatus?

    private enum AccountResult: Identifiable {
        case deleted, failed(String)
        var id: String { if case .failed(let text) = self { text } else { "deleted" } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TruffloScreenHeader(title: "Réglages", subtitle: "Votre journal vit sur cet iPhone.")
                        .padding(.top, 4)

                    section("Foyer") {
                        row("person.2", "Foyer partagé", detail: household.isSignedIn ? nil : "Non connecté",
                            identifier: "household.open") {
                            dismiss()
                            onOpenFoyer()
                        }
                        divider
                        @Bindable var household = household
                        Toggle(isOn: $household.sharesLivePosition) {
                            rowLabel("person.2.wave.2", "Chiens du foyer à proximité")
                        }
                        .tint(Color.truffloForest)
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("settings.nearby")
                    }

                    section("Rappels") {
                        row("bell", "Notifications", detail: notificationText) {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }

                    section("Données") {
                        row("square.and.arrow.up", "Exporter le journal", detail: "CSV et tracés GPX",
                            identifier: "journal.export") {
                            dismiss()
                            onExport()
                        }
                        divider
                        row("trash", "Effacer toutes les données", tint: .truffloDanger, chevron: false) {
                            confirmErase = true
                        }
                    }

                    if household.isSignedIn {
                        section("Compte") {
                            row("rectangle.portrait.and.arrow.right", "Se déconnecter", chevron: false) {
                                Task { await household.signOut() }
                            }
                            divider
                            row("person.crop.circle.badge.xmark", "Supprimer mon compte", tint: .truffloDanger,
                                chevron: false, isBusy: deletingAccount) {
                                confirmDeleteAccount = true
                            }
                        }
                    }

                    section("À propos") {
                        row("sparkles", "Revoir l'introduction") {
                            dismiss()
                            onShowIntroduction()
                        }
                        divider
                        HStack {
                            rowLabel("lock.shield", "Vos tracés restent sur cet iPhone")
                        }
                        .padding(.vertical, 10)
                        Text("Le foyer ne reçoit que les résumés de vos balades, jamais leur tracé ni vos notes.")
                            .font(.footnote)
                            .foregroundStyle(Color.truffloSlate)
                            .padding(.bottom, 8)
                    }

                    Text("Trufflo \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.bottom, TruffloTheme.Spacing.large)
            }
            .truffloAura()
            .truffloScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .task { notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
            .confirmationDialog("Effacer le journal et les chiens de cet iPhone ?",
                                isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) {
                    dismiss()
                    onErase()
                }
            } message: {
                Text(hasSharedData
                     ? "Cette suppression locale ne peut pas être annulée. Ce que vous avez déjà partagé avec le foyer y reste visible."
                     : "Cette suppression locale ne peut pas être annulée.")
            }
            .confirmationDialog("Supprimer votre compte Trufflo ?",
                                isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
                Button("Supprimer mon compte", role: .destructive) {
                    Task {
                        deletingAccount = true
                        let deleted = await household.deleteAccount()
                        deletingAccount = false
                        accountResult = deleted ? .deleted : .failed(household.errorMessage ?? "Réessayez plus tard.")
                    }
                }
            } message: {
                Text("Votre compte et ce que le serveur garde pour vous sont supprimés : vos balades partagées, votre nom dans le foyer. Le journal de cet iPhone reste.")
            }
            .alert(item: $accountResult) { result in
                switch result {
                case .deleted:
                    Alert(title: Text("Compte supprimé"),
                          message: Text("Votre compte n'existe plus. Votre journal reste sur cet iPhone."))
                case .failed(let text):
                    Alert(title: Text("Suppression impossible"), message: Text(text))
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var notificationText: String {
        switch notifications {
        case .authorized, .provisional, .ephemeral: "Activées"
        case .denied: "Refusées"
        case .notDetermined: "Pas encore demandées"
        default: ""
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.truffloForest.opacity(0.08)).frame(height: 1).padding(.leading, 40)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.truffloSlate)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
        }
    }

    private func rowLabel(_ icon: String, _ title: String, tint: Color = .truffloForest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(tint == .truffloDanger ? Color.truffloDanger : Color.truffloCharcoal)
        }
    }

    private func row(_ icon: String, _ title: String, detail: String? = nil, tint: Color = .truffloForest,
                     chevron: Bool = true, isBusy: Bool = false, identifier: String? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                rowLabel(icon, title, tint: tint)
                Spacer(minLength: 8)
                if isBusy {
                    ProgressView()
                } else if let detail {
                    Text(detail).font(.system(size: 14)).foregroundStyle(Color.truffloSlate)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.truffloSlate.opacity(0.6))
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(TruffloPressStyle())
        .disabled(isBusy)
        .accessibilityIdentifier(identifier ?? "")
    }
}
