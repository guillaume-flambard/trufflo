import SwiftUI

/// The dog as the subject of a screen: the photo edge to edge with the name set
/// over a scrim at the foot, or, with no photo, a sage field whose initial is
/// large and whose name sits below it in forest.
///
/// The two states are separate layouts on purpose. White text needs a dark
/// ground, and a pale sage field is not one, so without a photo the name is
/// forest on sage rather than white on a fade that was never there.
public struct TruffloDogHero: View {
    private let name: String
    private let photoData: Data?
    private let height: CGFloat

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    public init(name: String, photoData: Data?, height: CGFloat = 340) {
        self.name = name
        self.photoData = photoData
        self.height = height
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .overlay(alignment: .bottom) { scrim }
                nameLabel(color: .white)
            } else {
                Color.truffloSage.opacity(0.22)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        Text(initial)
                            .font(.system(size: 150, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.truffloForest.opacity(0.9))
                            .minimumScaleFactor(0.5)
                    }
                nameLabel(color: Color.truffloForest)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(image == nil ? "Portrait de \(name)" : "Photo de \(name)")
        .task(id: photoData) {
            // Decoded for the width of a phone, not for the stored resolution.
            image = photoData.flatMap {
                TruffloDogPortrait.downsampled($0, to: 430 * displayScale)
            }
        }
    }

    private var scrim: some View {
        LinearGradient(colors: [.clear, Color.truffloForestDeep.opacity(0.78)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height * 0.45)
            .allowsHitTesting(false)
    }

    private func nameLabel(color: Color) -> some View {
        Text(name)
            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, TruffloTheme.Spacing.large)
            .padding(.bottom, TruffloTheme.Spacing.medium)
            .accessibilityHidden(true)
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}
