import SwiftUI

/// "Qui part en balade ?" (PRD F06): shown only when there are several dogs, so
/// a household with one dog still starts in one tap. Every dog starts selected,
/// the common case being the whole pack; one tap removes a dog who stays home.
struct WhoIsWalkingSheet: View {
    let dogs: [DogRecord]
    let start: ([UUID]) -> Void
    let cancel: () -> Void

    @State private var selected: Set<UUID>

    init(dogs: [DogRecord], start: @escaping ([UUID]) -> Void, cancel: @escaping () -> Void) {
        self.dogs = dogs
        self.start = start
        self.cancel = cancel
        _selected = State(initialValue: Set(dogs.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
            Text("Qui part en balade ?")
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.truffloForest)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: TruffloTheme.Spacing.medium) {
                    ForEach(dogs) { dog in dogButton(dog) }
                }
                .padding(.vertical, 4)
            }

            VStack(spacing: TruffloTheme.Spacing.xSmall) {
                Button {
                    start(dogs.map(\.id).filter(selected.contains))
                } label: {
                    Text(selected.isEmpty ? "Choisissez au moins un chien" : "Démarrer")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.truffloForest)
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("walk.who.start")

                Button("Annuler", action: cancel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.truffloSlate)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, TruffloTheme.Spacing.large)
        .padding(.top, TruffloTheme.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.height(380)])
        .presentationBackground(Color.truffloSand)
    }

    private func dogButton(_ dog: DogRecord) -> some View {
        let isOn = selected.contains(dog.id)
        return Button {
            if isOn { selected.remove(dog.id) } else { selected.insert(dog.id) }
        } label: {
            VStack(spacing: TruffloTheme.Spacing.xSmall) {
                TruffloDogPortrait(name: dog.name, photoData: dog.photoData, diameter: 76)
                    .overlay(Circle().strokeBorder(isOn ? Color.truffloForest : Color.clear, lineWidth: 3))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isOn ? Color.truffloForest : Color.truffloSlate)
                            .background(Circle().fill(Color.truffloSand))
                    }
                    .opacity(isOn ? 1 : 0.55)
                Text(dog.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? Color.truffloForest : Color.truffloSlate)
                    .lineLimit(1)
            }
            .frame(width: 90)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dog.name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
