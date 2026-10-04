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
}

// MARK: - Typography Extensions
public extension Font {
    static var truffloTitle: Font {
        .system(size: 28, weight: .bold, design: .rounded)
    }
    static var truffloHeadline: Font {
        .system(size: 20, weight: .semibold, design: .rounded)
    }
    static var truffloSubheadline: Font {
        .system(size: 17, weight: .medium, design: .rounded)
    }
    static var truffloBody: Font {
        .system(size: 16, weight: .regular, design: .rounded)
    }
    static var truffloCaption: Font {
        .system(size: 13, weight: .regular, design: .rounded)
    }
}
