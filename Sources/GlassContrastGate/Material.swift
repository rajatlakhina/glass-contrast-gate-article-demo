import Foundation

/// The space in which a translucent layer is blended with what is behind it.
///
/// These two choices are not cosmetic. Gamma-encoded blending — the historical
/// default for UI compositing — and physically-correct linear-light blending
/// return measurably different colours for the same tint and the same opacity,
/// and therefore different contrast verdicts. The audit takes the blend space
/// as an explicit parameter instead of assuming one, because "which space does
/// this actually composite in?" is a question to measure on-device, not to
/// guess in a design review.
public enum BlendSpace: String, Sendable, CaseIterable {

    /// Blend the sRGB-encoded channel values directly.
    case gammaEncoded

    /// Convert to linear light, blend, convert back.
    case linearLight
}

/// A translucent chrome material: a tint applied at some opacity over whatever
/// happens to be behind it.
public struct Material: Sendable, Equatable {

    /// The material's own colour.
    public let tint: SRGBColor

    /// How much of the final colour the tint contributes, clamped to `0...1`.
    ///
    /// Read the complement: `1 - opacity` is the share of the background the
    /// app has handed to whatever content is passing underneath.
    public let opacity: Double

    public init(tint: SRGBColor, opacity: Double) {
        self.tint = tint
        if opacity.isFinite {
            self.opacity = Swift.min(1.0, Swift.max(0.0, opacity))
        } else {
            self.opacity = 1.0
        }
    }

    /// A fully opaque material — the pre-translucency case, where the app owns
    /// 100% of the background and the backdrop cannot affect anything.
    public static func opaque(_ tint: SRGBColor) -> Material {
        Material(tint: tint, opacity: 1.0)
    }

    /// The share of the composited background contributed by the backdrop
    /// rather than by the app's own tint.
    public var cededFraction: Double { 1.0 - opacity }

    /// Composites this material over `backdrop` in the given blend space.
    ///
    /// The two degenerate opacities are answered exactly rather than by
    /// arithmetic: a fully opaque material *is* its tint and a fully
    /// transparent one *is* the backdrop, and neither answer should depend on
    /// a round trip through a transfer function that costs a bit of precision.
    public func composited(over backdrop: SRGBColor,
                           in space: BlendSpace) -> SRGBColor {
        if opacity >= 1.0 { return tint }
        if opacity <= 0.0 { return backdrop }

        switch space {
        case .gammaEncoded:
            return SRGBColor(
                red: mix(tint.red, backdrop.red),
                green: mix(tint.green, backdrop.green),
                blue: mix(tint.blue, backdrop.blue))

        case .linearLight:
            let t = tint.linear
            let b = backdrop.linear
            return SRGBColor(
                red: SRGBColor.encode(mix(t.red, b.red)),
                green: SRGBColor.encode(mix(t.green, b.green)),
                blue: SRGBColor.encode(mix(t.blue, b.blue)))
        }
    }

    private func mix(_ over: Double, _ under: Double) -> Double {
        opacity * over + (1.0 - opacity) * under
    }
}
