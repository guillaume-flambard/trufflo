import SwiftUI

/// What it takes to appear in a zone: a name, the zone, and being an adult.
/// Says before anything else what others will see and what never leaves.
struct ProfileSetupView: View {
    @Environment(CommunityModel.self) private var model

    @State private var name = ""
    @State private var zoneID = ""
    @State private var isAdult = false

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { (1...40).contains(cleanName.count) && !zoneID.isEmpty && isAdult }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                    Text("Des sorties près de chez vous")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.truffloForest)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Des personnes de votre zone proposent des promenades à une date et un lieu précis. Vous demandez à venir, l'organisateur répond.")
                        .foregroundStyle(Color.truffloCharcoal)
                }

                CommunityErrorLine()

                field("Votre prénom ou pseudo") {
                    TextField("Camille", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("community.name")
                        .modifier(FormFieldStyle())
                }

                field("Votre zone") {
                    if model.zones.isEmpty {
                        Text("Aucune zone n'est ouverte pour l'instant.")
                            .foregroundStyle(Color.truffloSlate)
                    } else {
                        Picker("Zone", selection: $zoneID) {
                            ForEach(model.zones) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.truffloForest)
                        .accessibilityIdentifier("community.zone")
                    }
                }

                Toggle(isOn: $isAdult) {
                    Text("J'ai 18 ans ou plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.truffloCharcoal)
                }
                .tint(Color.truffloForest)
                .accessibilityIdentifier("community.adult")

                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
                    Text("Ce que les autres voient")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.truffloForest)
                    Text("Votre prénom, et les chiens que vous choisissez d'annoncer pour une sortie. Rien d'autre.")
                    Text("Jamais : votre position, vos tracés, vos notes, votre journal.")
                        .foregroundStyle(Color.truffloSlate)
                }
                .font(.subheadline)
                .foregroundStyle(Color.truffloCharcoal)

                Button {
                    Task { await model.saveProfile(displayName: cleanName, zoneID: zoneID, adultDeclared: isAdult) }
                } label: {
                    Text("Créer mon profil")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Color.truffloForest)
                .disabled(!canSave || model.isBusy)
                .accessibilityIdentifier("community.createProfile")
            }
            .padding(TruffloTheme.Spacing.large)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if zoneID.isEmpty { zoneID = model.zones.first?.id ?? "" } }
        .onChange(of: model.zones) { _, zones in if zoneID.isEmpty { zoneID = zones.first?.id ?? "" } }
        // The page names itself in large type: a bar title would say it twice.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Color.truffloSlate)
            content()
        }
    }
}
