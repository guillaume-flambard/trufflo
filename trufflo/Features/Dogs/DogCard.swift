import SwiftUI

/// The surface every card of the 2026-10-07 board shares: warm white, 22 pt
/// corners, a soft shadow. One place, so Chiens, the dog page and Today agree.
extension View {
    func truffloBoardCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}

/// What the person declared about the dog, as read-only chips: size, weight and
/// traits of character. Nothing read from the walks (product rule 3).
struct DogFactChips: View {
    let dog: DogRecord

    private var chips: [(icon: String, text: String)] {
        var list: [(String, String)] = []
        if let size = dog.size { list.append(("ruler", size.label)) }
        if let weight = dog.weightKg, weight > 0 {
            list.append(("scalemass", "\(weight.formatted(.number.precision(.fractionLength(0...1)).locale(TruffloLocale.french))) kg"))
        }
        list += dog.traits.map { ($0.systemImage, $0.label) }
        return list
    }

    var body: some View {
        if !chips.isEmpty {
            WrapLayout(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    Label(chip.text, systemImage: chip.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.truffloForest)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 26)
                        .background(Color(red: 0.89, green: 0.94, blue: 0.90), in: Capsule())
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// One dog on the Chiens tab: its photo, its name large, what was declared, and
/// two plain figures. No ranking between dogs.
struct TruffloDogCard: View {
    let dog: DogRecord
    let walkCount: Int
    let totalSeconds: TimeInterval

    private var declared: String {
        [dog.breedKind != "unknown" ? dog.breedDescription : "", dog.ageDescription,
         dog.genderDescription == "Non renseigné" ? "" : dog.genderDescription.lowercased()]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let photo = dog.photoData {
                    TruffloDogThumbnail(name: dog.name, photoData: photo, side: 84, bordered: false)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.truffloForest.opacity(0.7))
                        .frame(width: 84, height: 84)
                        .background(Color(red: 0.89, green: 0.94, blue: 0.90),
                                    in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(dog.name)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.truffloForest)
                    }
                    if !declared.isEmpty {
                        Text(declared)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.truffloSlate)
                            .lineLimit(2)
                    }
                    DogFactChips(dog: dog).padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                figure("figure.walk", "\(walkCount)", walkCount > 1 ? "balades" : "balade")
                Rectangle().fill(Color.truffloForest.opacity(0.12)).frame(width: 1, height: 34)
                figure("clock", walkCount == 0 ? "Pas encore" : WalkFormatting.minutes(totalSeconds), "en tout")
            }
            .padding(.vertical, 8)
            .background(Color(red: 0.95, green: 0.97, blue: 0.95), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .truffloBoardCard()
        .contentShape(Rectangle())
    }

    private func figure(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.truffloForest)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.truffloForest)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.truffloSlate)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
