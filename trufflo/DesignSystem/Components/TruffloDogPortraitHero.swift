import SwiftUI

/// The dog, full width, at the top of Today (ART-DIRECTION.md, TODAY A).
///
/// With a photo: the picture fills the frame under a scrim, and the name is
/// white on it. The scrim is what guarantees the contrast, whatever the photo.
/// Without one: the same mint aura as the head of Today, fading into the sand, and
/// the name in forest. No initial set large in its place: Today, the dog list and
/// the walk screens all refuse a stand-in face, and the profile now does too
/// (2026-10-07 review: the profile was the one screen drawing a giant letter).
/// The block is only as tall as its words, so the page does not open on a void.
struct TruffloDogPortraitHero<Footer: View>: View {
    let name: String
    let photoData: Data?
    let subtitle: String
    /// Share of the screen height the portrait takes: Today leads with it, the
    /// profile gives it a little more.
    var heightFactor: CGFloat = 0.46
    @ViewBuilder var footer: () -> Footer

    @State private var image: UIImage?
    /// Where in the photo the animal is, from 0 to 1, `y` from the top.
    @State private var focus = FocalCrop.fallbackFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Decoded to the width of the largest iPhone at 3x, not to the stored size.
    private var maxPixel: CGFloat { 1400 }

    private var hasPhoto: Bool { image != nil }
    private var textColor: Color { hasPhoto ? .white : Color.truffloForest }

    var body: some View {
        Group {
            if photoData != nil {
                ZStack(alignment: .bottomLeading) {
                    backdrop.ignoresSafeArea(edges: .top)
                    words
                }
                .containerRelativeFrame(.vertical) { height, _ in height * heightFactor }
                .clipped()
            } else {
                words
                    // Room for the navigation bar the hero runs under.
                    .padding(.top, 112)
                    .background(alignment: .top) {
                        TruffloDogAura(photoData: nil)
                            .frame(height: 420)
                            .ignoresSafeArea(edges: .top)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        // Not clipped as a whole: without a photo the aura runs on below the words
        // and fades into the page, as on Today.
        .accessibilityElement(children: .contain)
        .task(id: photoData) {
            let decoded = photoData.flatMap { TruffloDogPortrait.downsampled($0, to: maxPixel) }
            withAnimation(TruffloTheme.Motion.appear(reduceMotion: reduceMotion)) {
                image = decoded
            }
            // Off the main thread: Vision is synchronous.
            focus = await Task.detached(priority: .userInitiated) { [image] in
                image?.cgImage.map(DogFocus.focus(in:)) ?? FocalCrop.fallbackFocus
            }.value
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
            Text(name)
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(hasPhoto ? Color.white.opacity(0.92) : Color.truffloSlate)
            }
            footer()
                .padding(.top, TruffloTheme.Spacing.xSmall)
        }
        .padding(.horizontal, TruffloTheme.Spacing.screen)
        .padding(.bottom, TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let image {
            GeometryReader { proxy in
                let crop = FocalCrop.layout(imageSize: image.size, frame: proxy.size, focus: focus)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: crop.size.width, height: crop.size.height)
                    .offset(x: crop.offset.x, y: crop.offset.y)
                    .accessibilityLabel("Photo de \(name)")
            }
            .clipped()
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .clear, location: 0.4),
                                       .init(color: Color.black.opacity(0.62), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            // The system clock stays dark (the app is light-only), so it needs a light
            // field whatever the photo: a blur that fades out under the status bar.
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.thinMaterial)
                    .frame(height: 110)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
            }
        } else {
            // The photo is still decoding: the aura holds the place for a frame.
            TruffloDogAura(photoData: photoData)
        }
    }
}
