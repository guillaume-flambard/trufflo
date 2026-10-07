import SwiftUI

// The widget language of every screen (2026-10-07 review: "not one screen looks
// like another"). One container, one figure grid, one header, so Today, the
// Journal, the dogs and a balade read as the same app, the way an activity app
// builds every screen from the same cards.

/// The one container of the app: a white card on the sand, an optional small
/// title with its symbol, then the content.
struct TruffloWidget<Content: View>: View {
    var title: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
            if let title {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.truffloSlate)
                .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .truffloWidgetSurface()
    }
}

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

    /// The surface of a widget, for a card that lays out its own content: Liquid
    /// Glass, lightly filled so dark text stays readable on the sand and over the
    /// aura, with an opaque white under Reduce Transparency.
    func truffloWidgetSurface() -> some View {
        modifier(TruffloWidgetSurface())
    }
}

private struct TruffloWidgetSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous)
        if reduceTransparency {
            content.background(Color.white, in: shape)
        } else {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.55)), in: shape)
                .shadow(color: Color.truffloForest.opacity(0.08), radius: 16, x: 0, y: 6)
        }
    }
}

/// Figures in a two-column grid, a small label above each: the stats block of a
/// balade, a chien or a week. One column at accessibility sizes.
struct TruffloStatGrid: View {
    struct Item: Identifiable {
        let label: String
        let value: String
        var identifier: String? = nil
        var id: String { label }
    }

    let items: [Item]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: TruffloTheme.Spacing.medium, alignment: .topLeading),
                            count: typeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                    Text(item.value)
                        .font(.truffloFigure(.title2))
                        .monospacedDigit()
                        .foregroundStyle(Color.truffloForest)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(item.identifier ?? "")
            }
        }
    }
}

/// Who and when, at the head of a card or a page: a face when there is a photo,
/// the names, and one line of context.
struct TruffloCardHeader: View {
    let title: String
    let subtitle: String
    var photo: Data? = nil
    var photoName: String = ""
    var titleFont: Font = .truffloBodyHeavy

    var body: some View {
        HStack(alignment: .center, spacing: TruffloTheme.Spacing.small) {
            if let photo {
                TruffloDogPortrait(name: photoName, photoData: photo, diameter: 40, aimsAtAnimal: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(Color.truffloForest)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.truffloMeta)
                        .foregroundStyle(Color.truffloSlate)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
