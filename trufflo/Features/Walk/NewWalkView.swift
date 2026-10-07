import MapKit
import SwiftUI

/// The step before a balade (2026-10-07 mock-up): which dogs, how it is recorded,
/// where you are, then one button. The live screen opens only on "Démarrer".
///
/// Importing a GPX tracé is shown, as in the mock-up, but disabled and marked
/// "Bientôt": the app does not import tracés yet, and a tile that pretended to
/// would be a lie.
struct NewWalkView: View {
    let dogs: [DogRecord]
    let onStart: ([UUID]) -> Void
    let onManual: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: [UUID]
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showsSafetyNote = true

    init(dogs: [DogRecord], onStart: @escaping ([UUID]) -> Void, onManual: @escaping () -> Void) {
        self.dogs = dogs
        self.onStart = onStart
        self.onManual = onManual
        _selected = State(initialValue: dogs.first.map { [$0.id] } ?? [])
    }

    private var selectedDogs: [DogRecord] { dogs.filter { selected.contains($0.id) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nouvelle balade")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.truffloForest)
                        .accessibilityAddTraits(.isHeader)
                    Text("C'est parti ! Profitez du moment avec votre chien.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.truffloSlate)
                }
                .padding(.top, 56)

                dogRow
                modes
                mapPreview
                startButton
                counters
                if showsSafetyNote { safetyNote }
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.bottom, TruffloTheme.Spacing.large)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            ZStack(alignment: .top) {
                Color.truffloSand
                TruffloDogAura(photoData: nil).frame(height: 360)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.truffloCharcoal)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
            .padding(.leading, TruffloTheme.Spacing.screen)
            .padding(.top, 4)
        }
    }

    /// The dog going out, and a way to add or change it when there are several.
    private var dogRow: some View {
        HStack(spacing: TruffloTheme.Spacing.small) {
            Menu {
                ForEach(dogs) { dog in
                    Button {
                        selected = [dog.id]
                    } label: {
                        Label(dog.name, systemImage: selected == [dog.id] ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: TruffloTheme.Spacing.small) {
                    if let lead = selectedDogs.first {
                        TruffloDogPortrait(name: lead.name, photoData: lead.photoData, diameter: 44, aimsAtAnimal: true)
                    }
                    Text(selectedDogs.map(\.name).formatted(.list(type: .and).locale(TruffloLocale.french)))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.truffloCharcoal)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if dogs.count > 1 {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.truffloSlate)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .disabled(dogs.count < 2)
            .accessibilityIdentifier("walk.new.dog")

            if dogs.count > 1 {
                Menu {
                    ForEach(dogs.filter { !selected.contains($0.id) }) { dog in
                        Button(dog.name) { selected.append(dog.id) }
                    }
                } label: {
                    Label("Autre chien", systemImage: "plus.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.truffloForest)
                        .padding(.horizontal, 12)
                        .frame(height: 64)
                        .background(Color(red: 0.89, green: 0.94, blue: 0.90).opacity(0.9),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .disabled(selected.count == dogs.count)
            }
        }
    }

    /// GPS (chosen), manual (opens the form), GPX import (not yet).
    private var modes: some View {
        HStack(spacing: 6) {
            modeTile("figure.walk", "Enregistrer", "avec GPS", isOn: true, isEnabled: true) {}
            modeTile("map", "Balade manuelle", "sans GPS", isOn: false, isEnabled: true) {
                dismiss()
                onManual()
            }
            modeTile("point.topleft.down.to.point.bottomright.curvepath", "Depuis un tracé", "Bientôt",
                     isOn: false, isEnabled: false) {}
        }
        .padding(4)
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func modeTile(_ icon: String, _ title: String, _ subtitle: String,
                          isOn: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19))
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle).font(.system(size: 10)).opacity(0.8)
            }
            .foregroundStyle(isOn ? Color.white : Color.truffloForest)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(isOn ? Color.truffloForest : Color.clear,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Where you are, before you go: a still map on the person's position.
    private var mapPreview: some View {
        Map(position: $camera) {
            UserAnnotation()
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .including([.park])))
        .mapControlVisibility(.hidden)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(0..<3) { _ in Circle().fill(Color.truffloSage).frame(width: 5, height: 5) }
                }
                Text("Précision GPS").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.truffloForest)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.9), in: Capsule())
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            Button { camera = .userLocation(fallback: .automatic) } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.truffloForest)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recentrer la carte")
            .padding(10)
        }
        .accessibilityHidden(true)
    }

    private var startButton: some View {
        Button {
            let ids = selected
            dismiss()
            onStart(ids)
        } label: {
            Label("Démarrer la balade", systemImage: "play.fill")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(Color.truffloForest)
        .disabled(selected.isEmpty)
        .padding(.top, -34)
        .accessibilityIdentifier("walk.new.start")
    }

    /// The live figures as they will start: nothing recorded yet.
    private var counters: some View {
        HStack(spacing: 0) {
            counter("clock", "00:00", "Durée")
            Rectangle().fill(Color.truffloForest.opacity(0.12)).frame(width: 1, height: 44)
            counter("point.topleft.down.to.point.bottomright.curvepath", "0,00 km", "Distance")
            Rectangle().fill(Color.truffloForest.opacity(0.12)).frame(width: 1, height: 44)
            counter("gauge.with.needle", "0,0 km/h", "Allure")
        }
        .padding(.vertical, TruffloTheme.Spacing.small)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }

    private func counter(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Color.truffloForest)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Color.truffloForest)
            Text(label).font(.system(size: 11)).foregroundStyle(Color.truffloSlate)
        }
        .frame(maxWidth: .infinity)
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
            Image(systemName: "info.circle")
                .font(.system(size: 20))
                .foregroundStyle(Color.truffloForest)
            Text("Pensez à garder votre téléphone avec vous et à rester attentif à votre environnement.")
                .font(.system(size: 12))
                .foregroundStyle(Color.truffloForest)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { withAnimation { showsSafetyNote = false } } label: {
                Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(Color.truffloSlate)
                    .padding(10).contentShape(Rectangle()).padding(-10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Masquer le conseil")
        }
        .padding(TruffloTheme.Spacing.medium)
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
