import SwiftUI

/// Shown on Today when a walk cannot start, instead of opening the live screen
/// behind an alert: a walk that never began should not be on screen at all.
///
/// Each cause has its own wording and its own way out. Only a refusal is fixed
/// in Settings; a restriction or a device-wide switch is not, so those offer
/// manual entry as the primary action rather than a link that leads nowhere.
struct StartBlockedSheet: View {
    let block: LocationBlock
    let openSettings: () -> Void
    let addManually: () -> Void
    let dismiss: () -> Void

    private var title: String {
        switch block {
        case .permissionDenied: "Trufflo n'a pas accès à la position"
        case .permissionRestricted: "La localisation est restreinte"
        case .servicesUnavailable: "La localisation est désactivée"
        }
    }

    private var message: String {
        switch block {
        case .permissionDenied:
            "La localisation est refusée. Sans elle, le parcours ne peut pas s'enregistrer. Vous pouvez l'autoriser dans les réglages, ou noter la balade à la main."
        case .permissionRestricted:
            "Un réglage de l'appareil l'empêche, et Trufflo ne peut pas le modifier. La balade peut se noter à la main."
        case .servicesUnavailable:
            "Elle est coupée pour tout l'iPhone, dans Réglages, Confidentialité, Service de localisation. En attendant, la balade peut se noter à la main."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
            Image(systemName: block == .permissionDenied ? "location.slash" : "exclamationmark.circle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.truffloForest)
                .frame(width: 64, height: 64)
                .background(Color.truffloMint.opacity(0.45),
                            in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.truffloForest)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.truffloSlate)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: TruffloTheme.Spacing.xSmall) {
                if block.offersSettings {
                    Button(action: openSettings) {
                        Text("Ouvrir les réglages")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.truffloForest)
                    .truffloTap()
                    .accessibilityIdentifier("walk.blocked.settings")

                    Button(action: addManually) {
                        Text("Ajouter une balade passée")
                            .font(.headline)
                            .foregroundStyle(Color.truffloForest)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glass)
                    .truffloTap()
                    .accessibilityIdentifier("walk.blocked.manual")
                } else {
                    Button(action: addManually) {
                        Text("Ajouter une balade passée")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.truffloForest)
                    .truffloTap()
                    .accessibilityIdentifier("walk.blocked.manual")
                }
                Button("Plus tard", action: dismiss)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.truffloSlate)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .truffloTap()
                    .accessibilityIdentifier("walk.blocked.dismiss")
            }
            .padding(.top, TruffloTheme.Spacing.xSmall)
        }
        .padding(.horizontal, TruffloTheme.Spacing.screen)
        .padding(.top, TruffloTheme.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.height(560), .large])
        .presentationBackground(Color.truffloSand)
    }
}
