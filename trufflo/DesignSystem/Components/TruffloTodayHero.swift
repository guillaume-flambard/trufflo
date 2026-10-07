import SwiftUI

/// What sits behind the head of Today, under the status bar: the dog's photo on
/// the right two thirds, fading into the sand to the left and at the bottom so
/// the words on the left always sit on a calm field. The aura without a photo.
/// Placed behind the scroll view, so it stays put as the content moves over it.
struct TruffloTodayBackdrop: View {
    let name: String
    let photoData: Data?

    @State private var image: UIImage?
    @State private var focus = FocalCrop.fallbackFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        backdrop
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task(id: photoData) {
                let decoded = photoData.flatMap { TruffloDogPortrait.downsampled($0, to: 1200) }
                withAnimation(TruffloTheme.Motion.appear(reduceMotion: reduceMotion)) { image = decoded }
                focus = await Task.detached(priority: .userInitiated) { [image] in
                    image?.cgImage.map(DogFocus.focus(in:)) ?? FocalCrop.fallbackFocus
                }.value
            }
    }

    /// The photo on the right two thirds, fading into the sand to the left and
    /// at the bottom so the words on the left always sit on a calm field.
    @ViewBuilder
    private var backdrop: some View {
        if let image {
            // As in the mock-up: the photo fills the whole screen, behind every card,
            // the dog on the right of the head. A pale veil rises towards the bottom
            // so the cards stay readable, and a lighter one sits behind the greeting.
            GeometryReader { screen in
                // The photo covers the top of the screen (not its whole height, which
                // blew a dog's face up past the cards), then melts into the sand
                // behind the cards below.
                let frame = CGSize(width: screen.size.width, height: min(screen.size.height, 400))
                let scale = max(frame.width / image.size.width, frame.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let x = min(0, max(frame.width - size.width, frame.width * 0.68 - focus.x * size.width))
                let y = min(0, max(frame.height - size.height, frame.height * 0.3 - focus.y * size.height))
                Image(uiImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .offset(x: x, y: y)
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                    .clipped()
                    .overlay {
                        LinearGradient(stops: [.init(color: Color.truffloSand.opacity(0.12), location: 0),
                                               .init(color: .clear, location: 0.45)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black, location: 0.55),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.truffloSand)
            }
            .ignoresSafeArea()
            .accessibilityLabel("Photo de \(name)")
        } else {
            TruffloDogAura(photoData: nil)
                .frame(height: 480)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// A small tile of Today, measured on the 2026-10-07 mock-up: warm white, no
/// border, an outlined coloured symbol, a bold figure (or a short bold sentence),
/// and a grey line under it, centred in a 96 pt tile.
struct TruffloStatTile: View {
    let systemImage: String
    let tint: Color
    let value: String
    let label: String
    /// A sentence rather than a figure: set smaller, like the mock-up's third tile.
    var isSentence = false
    /// The mock-up sets a lone count smaller than a duration.
    var valueSize: CGFloat = 19
    var iconSize: CGFloat = 21

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: 18, alignment: .leading)
                .padding(.bottom, 8)
            // A fixed row, so the three tiles keep their figures on one line
            // whatever their size, and their labels start at the same height.
            Text(value)
                .font(.system(size: isSentence ? 15 : valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 22, alignment: .leading)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.42, green: 0.42, blue: 0.42))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        // Top-aligned in every tile: icons, figures and labels line up across the row.
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.984, green: 0.973, blue: 0.953).opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(red: 0.4, green: 0.3, blue: 0.15).opacity(0.05), radius: 12, y: 3)
        .accessibilityElement(children: .combine)
    }
}

/// A dog's photo as a small rounded square with a white edge, set in the corner of
/// a map or a card. Aimed at the dog, not at the middle of the photo.
struct TruffloDogThumbnail: View {
    let name: String
    let photoData: Data
    var side: CGFloat = 56
    /// Wider than tall when given; a square of `side` otherwise.
    var width: CGFloat? = nil
    /// The white edge of a face set over a map; none for a photo standing alone.
    var bordered = true

    @State private var image: UIImage?
    @State private var focus = FocalCrop.fallbackFocus
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous)
        let frame = CGSize(width: width ?? side, height: side)
        ZStack(alignment: .topLeading) {
            Color.truffloMint
            if let image {
                let crop = FocalCrop.layout(imageSize: image.size, frame: frame, focus: focus)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: crop.size.width, height: crop.size.height)
                    .offset(x: crop.offset.x, y: crop.offset.y)
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white, lineWidth: bordered ? 3 : 0))
        .shadow(color: .black.opacity(bordered ? 0.15 : 0), radius: 6, y: 3)
        .accessibilityLabel("Photo de \(name)")
        .task(id: photoData) {
            let decoded = TruffloDogPortrait.downsampled(photoData, to: 900)
            image = decoded
            focus = await Task.detached(priority: .userInitiated) {
                decoded?.cgImage.map(DogFocus.focus(in:)) ?? FocalCrop.fallbackFocus
            }.value
        }
    }
}
