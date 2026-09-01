import Foundation

/// A colour in the sRGB colour space, with each channel clamped to `0...1`.
///
/// This type deliberately carries no alpha. Translucency is a property of a
/// ``Material``, not of a colour, because the whole point of the audit is that
/// the *amount* of translucency is what decides how much of the background the
/// app still owns.
public struct SRGBColor: Sendable, Equatable, Hashable {

    public let red: Double
    public let green: Double
    public let blue: Double

    /// Creates a colour, clamping every channel into `0...1`.
    ///
    /// Clamping rather than trapping is deliberate: these values routinely
    /// arrive from a design-token file or a colour picker, and an audit tool
    /// that crashes on a token typo is an audit tool nobody runs in CI.
    public init(red: Double, green: Double, blue: Double) {
        self.red = SRGBColor.clamp(red)
        self.green = SRGBColor.clamp(green)
        self.blue = SRGBColor.clamp(blue)
    }

    /// Creates a colour from a 24-bit hex value, e.g. `0x0A84FF`.
    ///
    /// Only the low 24 bits are read, so a value with stray high bits is
    /// interpreted rather than rejected.
    public init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// A neutral grey at the given sRGB-encoded level.
    public static func grey(_ level: Double) -> SRGBColor {
        SRGBColor(red: level, green: level, blue: level)
    }

    public static let white = SRGBColor.grey(1.0)
    public static let black = SRGBColor.grey(0.0)

    /// Clamps into `0...1`. NaN — which has no direction to clamp toward —
    /// becomes `0`; the infinities clamp to the bound they are heading for.
    private static func clamp(_ value: Double) -> Double {
        if value.isNaN { return 0.0 }
        return Swift.min(1.0, Swift.max(0.0, value))
    }
}

// MARK: - WCAG luminance and contrast

extension SRGBColor {

    /// Converts a single sRGB-encoded channel to linear light,
    /// per the transfer function named in WCAG 2.1.
    static func linearize(_ channel: Double) -> Double {
        channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// The inverse of ``linearize(_:)``.
    static func encode(_ linear: Double) -> Double {
        linear <= 0.0031308
            ? linear * 12.92
            : 1.055 * pow(linear, 1.0 / 2.4) - 0.055
    }

    /// The same colour expressed in linear light.
    public var linear: (red: Double, green: Double, blue: Double) {
        (SRGBColor.linearize(red),
         SRGBColor.linearize(green),
         SRGBColor.linearize(blue))
    }

    /// WCAG 2.1 relative luminance.
    public var relativeLuminance: Double {
        let l = linear
        return 0.2126 * l.red + 0.7152 * l.green + 0.0722 * l.blue
    }

    /// The WCAG 2.1 contrast ratio between two colours, in `1.0...21.0`.
    ///
    /// The ratio is symmetric — the lighter colour is always the numerator —
    /// so callers never have to remember which argument is the foreground.
    public static func contrastRatio(_ a: SRGBColor, _ b: SRGBColor) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        let lighter = Swift.max(la, lb)
        let darker = Swift.min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
