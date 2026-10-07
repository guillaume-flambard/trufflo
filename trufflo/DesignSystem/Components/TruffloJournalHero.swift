import SwiftUI

/// The head of the Journal (2026-10-07 mock-up): the dog's photo across the top,
/// the title and one line in white over a dark veil, and a round "+" to add a
/// balade. The list then rises over the photo on a sand sheet. Without a photo,
/// the aura and forest words.
struct TruffloJournalHero: View {
    let title: String
    let subtitle: String
    let photoData: Data?
    let onAdd: (() -> Void)?

    @State private var image: UIImage?
    @State private var focus = FocalCrop.fallbackFocus
    /// The status bar's height, set by the screen the hero heads: the photo runs
    /// up under it.
    @Environment(\.heroTopInset) private var topInset
    private var height: CGFloat { 196 + topInset }

    private var hasPhoto: Bool { image != nil }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(hasPhoto ? Color.white : Color.truffloForest)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(hasPhoto ? Color.white.opacity(0.95) : Color.truffloSlate)
                    .frame(maxWidth: 200, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, TruffloTheme.Spacing.large)
            // Room for the sand sheet that overlaps the bottom of the photo.
            .padding(.bottom, 50)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Color.truffloForest)
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.tint(Color.white.opacity(0.7)).interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajouter une balade")
                .accessibilityIdentifier("walk.manual.add")
                .padding(.trailing, TruffloTheme.Spacing.large)
                .padding(.top, topInset + 8)
            }
        }
        .task(id: photoData) {
            let decoded = photoData.flatMap { TruffloDogPortrait.downsampled($0, to: 1400) }
            image = decoded
            focus = await Task.detached(priority: .userInitiated) {
                decoded?.cgImage.map(DogFocus.focus(in:)) ?? FocalCrop.fallbackFocus
            }.value
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let image {
            GeometryReader { proxy in
                let frame = proxy.size
                let scale = max(frame.width / image.size.width, frame.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                // The dog towards the right, as in the mock-up, the words on the left.
                let x = min(0, max(frame.width - size.width, frame.width * 0.62 - focus.x * size.width))
                let y = min(0, max(frame.height - size.height, frame.height * 0.5 - focus.y * size.height))
                Image(uiImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .offset(x: x, y: y)
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                    .clipped()
                    .overlay {
                        // Keeps white words readable on any photo.
                        LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0),
                                               .init(color: .clear, location: 0.7)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .overlay {
                        LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                               .init(color: .black.opacity(0.35), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .accessibilityHidden(true)
        } else {
            TruffloDogAura(photoData: nil)
        }
    }
}

/// The chips of the Journal: one choice among a few, the current one in forest.
struct TruffloFilterChips<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TruffloTheme.Spacing.xSmall) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    withAnimation(TruffloTheme.Motion.selection(reduceMotion: reduceMotion)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.white : Color(red: 0.2, green: 0.2, blue: 0.2))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(isOn ? Color.truffloForest : Color.black.opacity(0.05), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

extension EnvironmentValues {
    /// The top safe-area inset of the screen a photo head runs under.
    @Entry var heroTopInset: CGFloat = 0
}
