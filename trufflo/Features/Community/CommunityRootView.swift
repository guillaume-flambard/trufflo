import SwiftUI

struct EventRoute: Hashable { let id: UUID }

/// The « Sorties » tab (lot C). It exists only when the app has a community
/// server to talk to, and shows what that server said and nothing else.
struct CommunityRootView: View {
    @Environment(CommunityModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("Chargement des sorties")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsProfile:
                ProfileSetupView()
            case .failed(let message):
                TruffloNotice(systemImage: "wifi.exclamationmark", title: "Les sorties ne se chargent pas",
                              message: message, actionTitle: "Réessayer") { Task { await model.refresh() } }
            case .ready:
                EventsListView()
            }
        }
        .background(Color.truffloSand.ignoresSafeArea())
        .navigationDestination(for: EventRoute.self) { EventDetailView(eventID: $0.id) }
        .task { await model.refresh() }
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
