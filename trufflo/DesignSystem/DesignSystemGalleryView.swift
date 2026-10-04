import SwiftUI

/// Interactive SwiftUI Design System Showcase Gallery for Trufflo
public struct DesignSystemGalleryView: View {
    @State private var sampleText = "Oslo"
    @State private var selectedSegment = "Balades"

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    // MARK: - App Icon Header
                    HStack(spacing: TruffloTheme.Spacing.medium) {
                        Image("AppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trufflo Design System")
                                .font(.truffloHeadline)
                                .foregroundStyle(Color.truffloForest)
                            Text("À son rythme. Ensemble.")
                                .font(.truffloCaption)
                                .foregroundStyle(Color.truffloCharcoal.opacity(0.7))
                        }
                    }

                    Divider()

                    // MARK: - Color Tokens
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        Text("Couleurs").font(.truffloHeadline).foregroundStyle(Color.truffloForest)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: TruffloTheme.Spacing.small) {
                            colorSwatch("Forêt", color: .truffloForest)
                            colorSwatch("Sauge", color: .truffloSage)
                            colorSwatch("Menthe", color: .truffloMint)
                            colorSwatch("Sable", color: .truffloSand)
                            colorSwatch("Pêche", color: .truffloPeach)
                            colorSwatch("Terre", color: .truffloTerracotta)
                            colorSwatch("Ciel", color: .truffloSky)
                            colorSwatch("Chocolat", color: .truffloChocolate)
                            colorSwatch("Charbon", color: .truffloCharcoal)
                        }
                    }

                    Divider()

                    // MARK: - Typography Tokens
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        Text("Typographie (SF Pro Rounded)").font(.truffloHeadline).foregroundStyle(Color.truffloForest)
                        Text("Grand Titre").font(.truffloTitle).foregroundStyle(Color.truffloForest)
                        Text("Titre de Section").font(.truffloHeadline).foregroundStyle(Color.truffloForest)
                        Text("Sous-titre").font(.truffloSubheadline).foregroundStyle(Color.truffloCharcoal)
                        Text("Corps de texte").font(.truffloBody).foregroundStyle(Color.truffloCharcoal)
                        Text("Légende / Métadonnée").font(.truffloCaption).foregroundStyle(Color.truffloCharcoal.opacity(0.7))
                    }

                    Divider()

                    // MARK: - Buttons
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        Text("Boutons").font(.truffloHeadline).foregroundStyle(Color.truffloForest)

                        Button("Bouton Principal") {}
                            .buttonStyle(.truffloPrimary)
                        Button("Bouton Secondaire") {}
                            .buttonStyle(.truffloSecondary)
                        Button("Bouton Contour") {}
                            .buttonStyle(.truffloOutline)
                        Button("Bouton Discret") {}
                            .buttonStyle(.truffloGhost)
                    }

                    Divider()

                    // MARK: - Badges
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        Text("Badges & Puces").font(.truffloHeadline).foregroundStyle(Color.truffloForest)

                        HStack(spacing: TruffloTheme.Spacing.xSmall) {
                            TruffloBadge("Golden Retriever", icon: "pawprint.fill", style: .sage)
                            TruffloBadge("GPS", icon: "location.fill", style: .forest)
                            TruffloBadge("Balade", icon: "figure.walk", style: .peach)
                            TruffloBadge("Calme", icon: "heart.fill", style: .sky)
                        }
                    }

                    Divider()

                    // MARK: - Form Inputs
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        Text("Champs de texte & Contrôles").font(.truffloHeadline).foregroundStyle(Color.truffloForest)

                        TruffloTextField("Nom du chien", text: $sampleText, placeholder: "Ex: Oslo", icon: "pawprint")

                        TruffloSegmentedControl(
                            items: ["Balades", "Compagnons", "Profil"],
                            selection: $selectedSegment,
                            titleKeyPath: \.self
                        )
                    }

                    Divider()

                    // MARK: - Cards
                    VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                        Text("Cartes (TruffloCard)").font(.truffloHeadline).foregroundStyle(Color.truffloForest)

                        TruffloCard(variant: .sand) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Dernière balade d'Oslo").font(.truffloSubheadline).fontWeight(.semibold)
                                Text("32 min • 2,4 km").font(.truffloCaption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        TruffloCard(variant: .mint) {
                            HStack {
                                Image(systemName: "sun.max.fill").foregroundStyle(Color.truffloForest)
                                Text("Objectif hebdomadaire atteint !").font(.truffloBody).foregroundStyle(Color.truffloForest)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(TruffloTheme.Spacing.medium)
            }
            .navigationTitle("Design System")
        }
    }

    private func colorSwatch(_ name: String, color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: TruffloTheme.Radius.small)
                .fill(color)
                .frame(height: 50)
                .overlay(RoundedRectangle(cornerRadius: TruffloTheme.Radius.small).stroke(Color.black.opacity(0.08), lineWidth: 1))
            Text(name)
                .font(.truffloCaption)
                .foregroundStyle(Color.truffloCharcoal)
        }
    }
}

#Preview {
    DesignSystemGalleryView()
}
