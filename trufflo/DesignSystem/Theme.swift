import SwiftUI

/// Trufflo Design System Tokens & Branding
public enum TruffloTheme {
    // MARK: - Color Tokens
    public enum Colors {
        /// Forêt (#1E4D3B) - Primary brand green
        public static let forest = Color("ForestColor", bundle: .main)
        /// Sauge (#4CAF7B) - Secondary action green
        public static let sage = Color("SageColor", bundle: .main)
        /// Menthe (#A7D7C5) - Soft background green
        public static let mint = Color("MintColor", bundle: .main)
        /// Sable (#F7F4ED) - Primary app warm background
        public static let sand = Color("SandColor", bundle: .main)
        /// Pêche (#FFB38A) - Warm accent
        public static let peach = Color("PeachColor", bundle: .main)
        /// Terracotta (#D97656) - Earthy accent
        public static let terracotta = Color("TerracottaColor", bundle: .main)
        /// Ciel (#A7C7E7) - Soft sky blue
        public static let sky = Color("SkyColor", bundle: .main)
        /// Chocolat (#5C4033) - Warm brown text/elements
        public static let chocolate = Color("ChocolateColor", bundle: .main)
        /// Charbon (#2D2D2D) - High contrast dark text
        public static let charcoal = Color("CharcoalColor", bundle: .main)
        /// Terracotta foncée (#A94A2A) - Terminal actions and error text.
        ///
        /// The original terracotta (#D97656) tops out at 2.9:1 on sand and 3.1:1 as
        /// white text, so it works as an accent and nothing else. This darker variant
        /// reaches 5.1:1 on sand and 5.6:1 as white text, which is what a button
        /// label or an error message needs.
        public static let danger = Color("DangerColor", bundle: .main)
        /// Ambre (#B45309) - Weak GPS signal.
        public static let amber = Color("AmberColor", bundle: .main)
        /// Ardoise (#5B6472) - Legends and metadata.
        public static let slate = Color("SlateColor", bundle: .main)
        /// Forest profond (#14382B) - Opaque replacement for glass under
        /// Reduce Transparency, where a blurred surface is not legible.
        public static let forestDeep = Color(red: 20 / 255, green: 56 / 255, blue: 43 / 255)
    }

    // MARK: - Spacing Tokens
    public enum Spacing {
        public static let xxSmall: CGFloat = 4
        public static let xSmall: CGFloat = 8
        public static let small: CGFloat = 12
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
        public static let xLarge: CGFloat = 32
        public static let xxLarge: CGFloat = 48
    }

    // MARK: - Corner Radius Tokens
    public enum Radius {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 16
        public static let card: CGFloat = 20
        public static let pill: CGFloat = 999
    }
}

// MARK: - Color Convenience Extensions
public extension Color {
    static var truffloForest: Color { TruffloTheme.Colors.forest }
    static var truffloSage: Color { TruffloTheme.Colors.sage }
    static var truffloMint: Color { TruffloTheme.Colors.mint }
    static var truffloSand: Color { TruffloTheme.Colors.sand }
    static var truffloPeach: Color { TruffloTheme.Colors.peach }
    static var truffloTerracotta: Color { TruffloTheme.Colors.terracotta }
    static var truffloSky: Color { TruffloTheme.Colors.sky }
    static var truffloChocolate: Color { TruffloTheme.Colors.chocolate }
    static var truffloCharcoal: Color { TruffloTheme.Colors.charcoal }
    static var truffloDanger: Color { TruffloTheme.Colors.danger }
    static var truffloAmber: Color { TruffloTheme.Colors.amber }
    static var truffloSlate: Color { TruffloTheme.Colors.slate }
    static var truffloForestDeep: Color { TruffloTheme.Colors.forestDeep }
}

// MARK: - Typography Extensions
// Built on text styles so every size follows Dynamic Type.
public extension Font {
    static var truffloTitle: Font { .system(.title, design: .rounded, weight: .bold) }
    static var truffloHeadline: Font { .system(.title3, design: .rounded, weight: .semibold) }
    static var truffloSubheadline: Font { .system(.body, design: .rounded, weight: .medium) }
    static var truffloBody: Font { .system(.callout, design: .rounded, weight: .regular) }
    static var truffloCaption: Font { .system(.footnote, design: .rounded, weight: .regular) }
}

// MARK: - Screen chrome
public extension View {
    /// The one background and tint every list or form screen shares, so that
    /// Today, Journal, Dogs, detail and form screens read as the same app.
    func truffloScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.truffloSand.ignoresSafeArea())
            .tint(Color.truffloForest)
    }

    /// Legends, footers and metadata.
    func truffloSecondaryText() -> some View {
        self.font(.truffloCaption).foregroundStyle(Color.truffloSlate)
    }

    /// Error text: always readable (5:1 on sand) and never colour alone, the
    /// caller supplies the explicit sentence.
    func truffloErrorText() -> some View {
        self.font(.truffloCaption).foregroundStyle(Color.truffloDanger)
    }
}
