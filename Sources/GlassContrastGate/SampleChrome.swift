import Foundation

/// A plausible chrome inventory for a mid-sized app: the surfaces whose colours
/// were picked years ago against one flat bar colour, and never re-measured.
///
/// Every value here is the kind of thing that lives in a design-token file and
/// gets copied forward through three redesigns without anyone re-deriving it.
public enum SampleChrome {

    /// The flat bar colour the design system declares. Historically this *was*
    /// the background, so checking against it was correct.
    public static let nominalBackdrop = SRGBColor(hex: 0xF2F2F7)

    /// A light chrome material: near-white tint at 70% — the app keeps 70% of
    /// its background and hands 30% to whatever scrolls underneath.
    public static let lightGlass = Material(tint: SRGBColor(hex: 0xF2F2F7), opacity: 0.70)

    /// A thinner material used for search and filter chrome.
    public static let thinGlass = Material(tint: SRGBColor(hex: 0xF2F2F7), opacity: 0.50)

    /// Every surface here clears its WCAG requirement against ``nominalBackdrop``.
    /// That is the point: this is not a broken design system. It is a design
    /// system that passed, under an assumption that stopped being true.
    public static let surfaces: [SurfaceBaseline] = [
        SurfaceBaseline(
            id: "NavigationBar/Title",
            foreground: SRGBColor(hex: 0x1C1C1E),
            material: lightGlass,
            requirement: .largeText),

        SurfaceBaseline(
            id: "NavigationBar/BrandAction",
            foreground: SRGBColor(hex: 0x0051B8),
            material: lightGlass,
            requirement: .normalText),

        SurfaceBaseline(
            id: "Toolbar/SecondaryLabel",
            foreground: SRGBColor(hex: 0x6C6C70),
            material: lightGlass,
            requirement: .normalText),

        SurfaceBaseline(
            id: "TabBar/SelectedIcon",
            foreground: SRGBColor(hex: 0x007AFF),
            material: lightGlass,
            requirement: .nonText),

        SurfaceBaseline(
            id: "SearchField/Placeholder",
            foreground: SRGBColor(hex: 0x4A4A4E),
            material: thinGlass,
            requirement: .normalText),

        SurfaceBaseline(
            id: "Toolbar/DestructiveAction",
            foreground: SRGBColor(hex: 0xB3000C),
            material: lightGlass,
            requirement: .normalText)
    ]

    /// The audit as the demo app runs it.
    public static func audit(blendSpace: BlendSpace = .gammaEncoded,
                             sweepSteps: Int = 21) throws -> ChromeAuthorityAudit {
        ChromeAuthorityAudit(
            nominalBackdrop: nominalBackdrop,
            envelope: try BackdropEnvelope.greySweep(count: sweepSteps),
            blendSpace: blendSpace)
    }
}
