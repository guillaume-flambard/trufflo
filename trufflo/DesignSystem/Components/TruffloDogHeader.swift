import SwiftUI

/// The dog at the head of Today: a portrait, its name, one line of facts, and
/// whatever invitation the screen has for it (A2-REQ-05).
///
/// With a photo the portrait aims at the animal. Without one nothing is drawn in
/// its place: no initial on a disc, no silhouette, because a stand-in face is a
/// face that is not theirs. The name carries the header alone, and the footer
/// says how to add the photo.
struct TruffloDogHeader<Footer: View>: View {
    let name: String
    let photoData: Data?
    let subtitle: String
    @ViewBuilder var footer: () -> Footer

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: TruffloTheme.Spacing.small))
            : AnyLayout(HStackLayout(alignment: .center, spacing: TruffloTheme.Spacing.medium))
        layout {
            if let photoData {
                TruffloDogPortrait(name: name, photoData: photoData, diameter: 64, aimsAtAnimal: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.truffloTitleHeavy)
                    .foregroundStyle(Color.truffloForest)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.truffloBodyRegular)
                        .foregroundStyle(Color.truffloSlate)
                }
                footer().padding(.top, TruffloTheme.Spacing.xxSmall)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
