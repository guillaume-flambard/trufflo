import SwiftUI

/// Report an outing or a person (Apple 1.2: a way to report, and a timely
/// answer). The reason is chosen, the detail is optional and short.
struct ReportSheet: View {
    let target: ReportTarget
    let targetID: UUID
    let title: String

    @Environment(CommunityModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ReportReason.inappropriate
    @State private var detail = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    if sent {
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                            Label("Signalement envoyé", systemImage: "checkmark.circle")
                                .font(.system(.title2, design: .rounded, weight: .heavy))
                                .foregroundStyle(Color.truffloForest)
                            Text("Une personne de l'équipe le lit. Vous pouvez aussi bloquer la personne concernée pour ne plus la croiser, depuis le menu de la sortie.")
                                .foregroundStyle(Color.truffloCharcoal)
                            Button("Fermer") { dismiss() }
                                .font(.headline)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("report.close")
                        }
                        .accessibilityIdentifier("report.sent")
                    } else {
                        Text("Signaler")
                            .font(.system(.title, design: .rounded, weight: .heavy))
                            .foregroundStyle(Color.truffloForest)
                        Text(title).foregroundStyle(Color.truffloSlate)
                        CommunityErrorLine()

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(ReportReason.allCases, id: \.self) { item in
                                Button { reason = item } label: {
                                    HStack {
                                        Text(Self.label(item)).foregroundStyle(Color.truffloCharcoal)
                                        Spacer()
                                        Image(systemName: reason == item ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(Color.truffloForest)
                                            .accessibilityHidden(true)
                                    }
                                    .frame(minHeight: 48)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(reason == item ? .isSelected : [])
                                .accessibilityIdentifier("report.reason.\(item.rawValue)")
                            }
                        }

                        TextField("Ce qui s'est passé, si vous voulez (500 caractères)", text: $detail, axis: .vertical)
                            .lineLimit(2...5)
                            .modifier(FormFieldStyle())
                            .accessibilityIdentifier("report.detail")

                        Button {
                            Task { sent = await model.report(target, id: targetID, reason: reason, detail: String(detail.prefix(500))) }
                        } label: {
                            Text("Envoyer le signalement")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Color.truffloForest)
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("report.send")
                    }
                }
                .padding(TruffloTheme.Spacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.truffloSand.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(sent ? "Fermer" : "Annuler") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    static func label(_ reason: ReportReason) -> String {
        switch reason {
        case .danger: "Danger ou menace"
        case .harassment: "Harcèlement"
        case .inappropriate: "Contenu inapproprié"
        case .spam: "Indésirable ou publicité"
        case .other: "Autre"
        }
    }
}

/// The people this person blocked, each one undoable.
struct BlockedPeopleView: View {
    @Environment(CommunityModel.self) private var model

    var body: some View {
        List {
            if model.blocked.isEmpty {
                Text("Vous n'avez bloqué personne.")
                    .foregroundStyle(Color.truffloSlate)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("blocked.empty")
            }
            ForEach(model.blocked) { person in
                HStack {
                    Text(person.displayName).foregroundStyle(Color.truffloCharcoal)
                    Spacer()
                    Button("Débloquer") { Task { await model.unblock(person.userID) } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.truffloForest)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("blocked.unblock.\(person.displayName)")
                }
                .listRowBackground(Color.clear)
            }
            Section {
                Text("Une personne bloquée ne voit plus vos sorties, et vous ne voyez plus les siennes.")
                    .font(.footnote)
                    .foregroundStyle(Color.truffloSlate)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.truffloSand.ignoresSafeArea())
        .navigationTitle("Personnes bloquées")
        .navigationBarTitleDisplayMode(.inline)
    }
}
