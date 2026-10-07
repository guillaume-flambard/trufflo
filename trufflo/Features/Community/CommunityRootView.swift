import SwiftUI

struct OutingRoute: Hashable { let id: UUID }

/// The « Sorties » tab (lot C). It exists only when the app has a community
/// server to talk to, and shows what that server said and nothing else.
struct CommunityRootView: View {
    @Environment(CommunityModel.self) private var model
    @State private var showSignIn = false

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("Chargement des sorties")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsSignIn:
                TruffloNotice(systemImage: "person.crop.circle.badge.questionmark",
                              title: "Connectez-vous pour voir les sorties",
                              message: "Les sorties passent par le même compte Apple que le foyer partagé. Vos balades et vos notes restent sur cet iPhone.",
                              actionTitle: "Se connecter avec Apple") { showSignIn = true }
                    .accessibilityIdentifier("community.signin")
            case .needsProfile:
                ProfileSetupView()
            case .failed(let message):
                TruffloNotice(systemImage: "wifi.exclamationmark", title: "Les sorties ne se chargent pas",
                              message: message, actionTitle: "Réessayer") { Task { await model.refresh() } }
            case .ready:
                OutingsListView()
            }
        }
        .background(Color.truffloSand.ignoresSafeArea())
        .navigationDestination(for: OutingRoute.self) { OutingDetailView(outingID: $0.id) }
        .task { await model.refresh() }
        // The sign-in is the household's: same account, same session.
        .sheet(isPresented: $showSignIn, onDismiss: { Task { await model.refresh() } }) { HouseholdView() }
    }
}

/// Said once, at the top of a screen, and cleared by the person.
struct CommunityErrorLine: View {
    @Environment(CommunityModel.self) private var model

    var body: some View {
        if let message = model.errorMessage {
            HStack(alignment: .top, spacing: TruffloTheme.Spacing.xSmall) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color.truffloDanger)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.truffloCharcoal)
                Spacer(minLength: 0)
                Button("Fermer", systemImage: "xmark") { model.errorMessage = nil }
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.truffloSlate)
                    .frame(width: 44, height: 44)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("community.error")
        }
    }
}
