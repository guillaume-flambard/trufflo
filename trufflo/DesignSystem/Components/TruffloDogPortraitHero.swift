import SwiftUI

/// The dog, full width, at the top of Today (ART-DIRECTION.md, TODAY A).
///
/// With a photo: the picture fills the frame under a scrim, and the name is
/// white on it. The scrim is what guarantees the contrast, whatever the photo.
/// Without one: a pale sage field with the initial set large and quiet, and the
/// name in forest. The screen stays sober rather than reaching for a gradient to
/// make up for the missing picture.
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

    /// Decoded to the width of the largest iPhone at 3x, not to the stored size.
    private var maxPixel: CGFloat { 1400 }

    private var hasPhoto: Bool { image != nil }
    private var textColor: Color { hasPhoto ? .white : Color.truffloForest }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop.ignoresSafeArea(edges: .top)
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
            .padding(.horizontal, TruffloTheme.Spacing.medium)
            .padding(.bottom, TruffloTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerRelativeFrame(.vertical) { height, _ in height * heightFactor }
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityElement(children: .contain)
        .task(id: photoData) {
            image = photoData.flatMap { TruffloDogPortrait.downsampled($0, to: maxPixel) }
            // Off the main thread: Vision is synchronous.
            focus = await Task.detached(priority: .userInitiated) { [image] in
                image?.cgImage.map(DogFocus.focus(in:)) ?? FocalCrop.fallbackFocus
            }.value
        }
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
            Color(red: 0.83, green: 0.92, blue: 0.88)
                .overlay(alignment: .center) {
                    Text(initial)
                        .font(.system(size: 160, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.truffloForest.opacity(0.14))
                        .accessibilityHidden(true)
                }
        }
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}
