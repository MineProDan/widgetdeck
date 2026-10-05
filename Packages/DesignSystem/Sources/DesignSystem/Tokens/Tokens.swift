import CoreKit
import CoreGraphics

// Three token layers (docs/plan/06 §1.1):
//   Primitive  → raw values. NEVER referenced by feature code.
//   Semantic   → roles (surface.base, text.primary, …). Redefined per Theme and per light/dark.
//   Component  → sizes/insets for components. Consume semantic tokens only.
// Themes swap ONLY the semantic layer; that is what makes one-tap Theme Sync possible.

/// Layer 1: primitive palette and scales. Internal on purpose: features use semantic tokens
/// (or the Paint Chip `WXColor` paints, which are fixed and theme-independent).
enum Primitive {
    /// Paint Chip neutrals and paints (DESIGN.md frontmatter).
    enum Paint {
        static let paperIvory = RGBAColor(hex: "#F7F3EA")!
        static let labelIvory = RGBAColor(hex: "#FFFDF8")!
        static let ink = RGBAColor(hex: "#22232E")!
        static let inkSecondary = RGBAColor(hex: "#5B5D6B")!
        static let rule = RGBAColor(hex: "#E4DED1")!
        static let clayLink = RGBAColor(hex: "#B2492F")!
        static let mossPositive = RGBAColor(hex: "#4C7A62")!
        static let deepTide = RGBAColor(hex: "#3D405B")!
    }

    enum Sand {
        static let c50 = RGBAColor(hex: "#FBF8F3")!
        static let c100 = RGBAColor(hex: "#F5EFE6")!
        static let c200 = RGBAColor(hex: "#EADFCF")!
        static let c300 = RGBAColor(hex: "#DCCBB3")!
        static let c500 = RGBAColor(hex: "#B39A78")!
        static let c700 = RGBAColor(hex: "#7A6446")!
        static let c900 = RGBAColor(hex: "#3D3122")!
    }

    enum Ink {
        static let c100 = RGBAColor(hex: "#E6E7EB")!
        static let c300 = RGBAColor(hex: "#A3A7B3")!
        static let c500 = RGBAColor(hex: "#5E6372")!
        static let c600 = RGBAColor(hex: "#474B57")!
        static let c700 = RGBAColor(hex: "#30333C")!
        static let c800 = RGBAColor(hex: "#1E2027")!
        static let c900 = RGBAColor(hex: "#121318")!
        static let c950 = RGBAColor(hex: "#0A0B0E")!
    }

    enum Accent {
        static let coral600 = RGBAColor(hex: "#C2410C")!
        static let coral300 = RGBAColor(hex: "#FDA47E")!
        static let green600 = RGBAColor(hex: "#15803D")!
        static let green300 = RGBAColor(hex: "#6EE7A0")!
        static let amber600 = RGBAColor(hex: "#B45309")!
        static let amber300 = RGBAColor(hex: "#FCD34D")!
        static let red600 = RGBAColor(hex: "#B91C1C")!
        static let red300 = RGBAColor(hex: "#FCA5A5")!
    }
}

/// Spacing scale (points). Public: spacing is layout, not color, so features may use it.
public enum Space {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

/// Corner radius scale (points).
public enum Radius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let full: CGFloat = 999
}

/// Layer 2: semantic colors. One instance per theme per color scheme.
public struct SemanticPalette: Hashable, Sendable {
    public var surfaceBase: RGBAColor
    public var surfaceElevated: RGBAColor
    public var textPrimary: RGBAColor
    public var textSecondary: RGBAColor
    public var accentPrimary: RGBAColor
    /// Text/icons drawn on `accentPrimary`.
    public var onAccent: RGBAColor
    public var border: RGBAColor
    public var stateSuccess: RGBAColor
    public var stateWarning: RGBAColor
    public var stateError: RGBAColor

    public init(surfaceBase: RGBAColor, surfaceElevated: RGBAColor, textPrimary: RGBAColor, textSecondary: RGBAColor,
                accentPrimary: RGBAColor, onAccent: RGBAColor, border: RGBAColor,
                stateSuccess: RGBAColor, stateWarning: RGBAColor, stateError: RGBAColor) {
        self.surfaceBase = surfaceBase
        self.surfaceElevated = surfaceElevated
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accentPrimary = accentPrimary
        self.onAccent = onAccent
        self.border = border
        self.stateSuccess = stateSuccess
        self.stateWarning = stateWarning
        self.stateError = stateError
    }

    /// Default light palette: the Paint Chip neutrals (Paper Ivory ground, Label Ivory surfaces,
    /// Ink text, Clay Link accent, Moss Positive success). All text pairs meet WCAG AA (verified in tests).
    public static let light = SemanticPalette(
        surfaceBase: Primitive.Paint.paperIvory, surfaceElevated: Primitive.Paint.labelIvory,
        textPrimary: Primitive.Paint.ink, textSecondary: Primitive.Paint.inkSecondary,
        accentPrimary: Primitive.Paint.clayLink, onAccent: Primitive.Paint.labelIvory, border: Primitive.Paint.rule,
        stateSuccess: Primitive.Paint.mossPositive, stateWarning: Primitive.Paint.clayLink, stateError: Primitive.Paint.clayLink
    )

    /// Default dark palette.
    public static let dark = SemanticPalette(
        surfaceBase: Primitive.Ink.c950, surfaceElevated: Primitive.Ink.c800,
        textPrimary: Primitive.Ink.c100, textSecondary: Primitive.Ink.c300,
        accentPrimary: Primitive.Accent.coral300, onAccent: Primitive.Ink.c950, border: Primitive.Ink.c700,
        stateSuccess: Primitive.Accent.green300, stateWarning: Primitive.Accent.amber300, stateError: Primitive.Accent.red300
    )
}

/// Layer 3: component tokens. Sizes only; colors come from the semantic palette.
public enum ComponentTokens {
    public enum Card {
        public static let padding: CGFloat = Space.md
        public static let cornerRadius: CGFloat = Radius.md
        public static let borderWidth: CGFloat = 1
    }

    public enum Gauge {
        public static let trackWidth: CGFloat = 10
        public static let accessoryTrackWidth: CGFloat = 5
    }

    public enum Chip {
        /// Apple HIG minimum hit target.
        public static let minHeight: CGFloat = 44
        public static let horizontalPadding: CGFloat = Space.sm
    }

    public enum Widget {
        public static let cornerInset: CGFloat = Space.md
        public static let accessoryInset: CGFloat = 0
    }
}
