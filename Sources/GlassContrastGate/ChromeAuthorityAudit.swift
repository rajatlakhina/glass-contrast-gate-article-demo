import Foundation

/// What the audit concluded about one surface.
public struct SurfaceVerdict: Sendable, Equatable {

    public let surfaceID: String
    public let requiredRatio: Double

    /// Contrast against the single nominal backdrop the design system declares —
    /// i.e. the number the old check produced.
    public let nominalRatio: Double

    /// The lowest contrast found anywhere in the envelope.
    public let worstCaseRatio: Double

    /// The backdrop that produced ``worstCaseRatio``. This is the evidence: it
    /// is a colour someone can reproduce on a device in ten seconds.
    public let worstCaseBackdrop: SRGBColor

    /// The composited background at the worst case, after the material has been
    /// blended over ``worstCaseBackdrop``.
    public let worstCaseBackground: SRGBColor

    public var passesNominal: Bool { nominalRatio >= requiredRatio }
    public var passesEnvelope: Bool { worstCaseRatio >= requiredRatio }

    /// The class of defect this whole exercise exists to find: a surface that
    /// has passed every review for years against one declared background, and
    /// fails once the background stops being the app's to declare.
    public var isSilentRegression: Bool { passesNominal && !passesEnvelope }

    /// How much contrast the nominal check was over-reporting.
    public var overstatement: Double { nominalRatio - worstCaseRatio }
}

/// The report for one run of the audit.
public struct AuditReport: Sendable, Equatable {

    public let verdicts: [SurfaceVerdict]
    public let blendSpace: BlendSpace
    public let envelopeName: String

    public var silentRegressions: [SurfaceVerdict] { verdicts.filter(\.isSilentRegression) }
    public var envelopeFailures: [SurfaceVerdict] { verdicts.filter { !$0.passesEnvelope } }
    public var nominalFailures: [SurfaceVerdict] { verdicts.filter { !$0.passesNominal } }

    /// The gate result. A surface that already failed nominally is a known bug;
    /// a surface that only fails against the envelope is a new one.
    public var passes: Bool { envelopeFailures.isEmpty }

    /// The largest gap between what the nominal check claimed and what the
    /// envelope actually delivers, across every surface.
    public var worstOverstatement: Double {
        verdicts.map(\.overstatement).max() ?? 0.0
    }
}

/// Evaluates chrome contrast across a range of backdrops rather than against a
/// single declared one.
public struct ChromeAuthorityAudit: Sendable {

    /// The background the design system claims the chrome sits on — the
    /// assumption the app used to be allowed to make.
    public let nominalBackdrop: SRGBColor

    public let envelope: BackdropEnvelope
    public let blendSpace: BlendSpace

    public init(nominalBackdrop: SRGBColor,
                envelope: BackdropEnvelope,
                blendSpace: BlendSpace) {
        self.nominalBackdrop = nominalBackdrop
        self.envelope = envelope
        self.blendSpace = blendSpace
    }

    public func evaluate(_ surfaces: [SurfaceBaseline]) -> AuditReport {
        AuditReport(verdicts: surfaces.map(verdict(for:)),
                    blendSpace: blendSpace,
                    envelopeName: envelope.name)
    }

    public func verdict(for surface: SurfaceBaseline) -> SurfaceVerdict {
        let nominalBackground = surface.material.composited(over: nominalBackdrop,
                                                            in: blendSpace)
        let nominalRatio = SRGBColor.contrastRatio(surface.foreground, nominalBackground)

        // `samples` is non-empty by construction — BackdropEnvelope.init throws
        // on an empty set — but the reduce is written so that an empty array
        // would degrade to the nominal case rather than trap.
        var worstRatio = Double.infinity
        var worstBackdrop = nominalBackdrop
        var worstBackground = nominalBackground

        for backdrop in envelope.samples {
            let background = surface.material.composited(over: backdrop, in: blendSpace)
            let ratio = SRGBColor.contrastRatio(surface.foreground, background)
            if ratio < worstRatio {
                worstRatio = ratio
                worstBackdrop = backdrop
                worstBackground = background
            }
        }

        if worstRatio == .infinity {
            worstRatio = nominalRatio
        }

        return SurfaceVerdict(surfaceID: surface.id,
                              requiredRatio: surface.requirement.minimumRatio,
                              nominalRatio: nominalRatio,
                              worstCaseRatio: worstRatio,
                              worstCaseBackdrop: worstBackdrop,
                              worstCaseBackground: worstBackground)
    }
}
