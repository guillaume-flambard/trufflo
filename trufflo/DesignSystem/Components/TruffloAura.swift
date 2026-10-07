import SwiftUI

extension View {
    /// The mint aura at the head of a screen, under the bars, fading into the sand:
    /// the same backdrop on every tab, and something for the glass to catch.
    func truffloAura(photoData: Data? = nil) -> some View {
        background(alignment: .top) {
            TruffloDogAura(photoData: photoData)
                .frame(height: 420)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

}
