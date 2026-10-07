import SwiftUI

/// The top of Today takes the dog's colours: a soft mesh computed from the photo
/// (`DogPalette`), fading into the page. Each dog gets its own screen, the way a
/// now-playing screen takes its cover's colours, and a dog with no photo gets the
/// brand's mint.
///
/// It is the page's own colour, not glass, so it sits behind content like any
/// background. It is still: no drift, no loop (a permanent motion is a permanent
/// cost). The palette is softened until slate text holds 4.5:1 on every cell, so
/// the photo cannot make the words unreadable.
struct TruffloDogAura: View {
    let photoData: Data?

    @State private var palette: [DogPalette.RGB] = DogPalette.fallback

    var body: some View {
        MeshGradient(width: 3, height: 3,
                     // The inner points are nudged off the grid so the colours meet in
                     // soft bends rather than straight bands.
                     points: [[0, 0], [0.5, 0], [1, 0],
                              [0, 0.5], [0.58, 0.44], [1, 0.52],
                              [0, 1], [0.46, 1], [1, 1]],
                     colors: palette.map(Color.init))
            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                         .init(color: .black, location: 0.55),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .animation(.easeInOut(duration: 0.7), value: palette)
            .accessibilityHidden(true)
            .task(id: photoData) {
                guard let photoData else {
                    palette = DogPalette.fallback
                    return
                }
                // Off the main thread: decoding and averaging a photo is not free.
                palette = await Task.detached(priority: .userInitiated) {
                    TruffloDogPortrait.downsampled(photoData, to: 96)?.cgImage
                        .map(DogPalette.colors(from:)) ?? DogPalette.fallback
                }.value
            }
    }
}

private extension Color {
    init(_ rgb: DogPalette.RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

#Preview("Aura sans photo") {
    TruffloDogAura(photoData: nil)
        .frame(height: 420)
        .background(Color.truffloSand)
}
