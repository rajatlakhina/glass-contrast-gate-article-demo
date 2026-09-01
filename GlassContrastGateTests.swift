import XCTest
@testable import GlassContrastGate

final class ContrastMathTests: XCTestCase {

    func testWCAGBoundsAreExact() {
        XCTAssertEqual(SRGBColor.contrastRatio(.white, .black), 21.0, accuracy: 0.0001)
        XCTAssertEqual(SRGBColor.contrastRatio(.white, .white), 1.0, accuracy: 0.0001)
    }

    func testContrastRatioIsSymmetric() {
        let a = SRGBColor(hex: 0x0051B8)
        let b = SRGBColor(hex: 0xF2F2F7)
        XCTAssertEqual(SRGBColor.contrastRatio(a, b),
                       SRGBColor.contrastRatio(b, a),
                       accuracy: 1e-12)
    }

    func testRelativeLuminanceEndpoints() {
        XCTAssertEqual(SRGBColor.white.relativeLuminance, 1.0, accuracy: 1e-9)
        XCTAssertEqual(SRGBColor.black.relativeLuminance, 0.0, accuracy: 1e-9)
    }

    func testLinearizeAndEncodeRoundTrip() {
        for step in 0...100 {
            let channel = Double(step) / 100.0
            let round = SRGBColor.encode(SRGBColor.linearize(channel))
            XCTAssertEqual(round, channel, accuracy: 1e-9)
        }
    }

    /// Out-of-range and non-finite channels are clamped, not trapped — an audit
    /// that crashes on a bad design token never runs in CI.
    func testChannelsAreClampedNotTrapped() {
        let over = SRGBColor(red: 4.2, green: -1.0, blue: 0.5)
        XCTAssertEqual(over.red, 1.0)
        XCTAssertEqual(over.green, 0.0)
        XCTAssertEqual(over.blue, 0.5)

        let nan = SRGBColor(red: .nan, green: .infinity, blue: 0.25)
        XCTAssertEqual(nan.red, 0.0)
        XCTAssertEqual(nan.green, 1.0)
        XCTAssertEqual(nan.blue, 0.25)
    }

    func testHexInitReadsOnlyLow24Bits() {
        XCTAssertEqual(SRGBColor(hex: 0xFF0A84FF), SRGBColor(hex: 0x0A84FF))
    }
}

final class MaterialTests: XCTestCase {

    /// The thesis of the library in one assertion: at full opacity the backdrop
    /// cannot move the composited colour at all. Every bit of contrast risk
    /// enters through `1 - opacity`.
    func testOpaqueMaterialIgnoresBackdrop() {
        let material = Material.opaque(SRGBColor(hex: 0xF2F2F7))
        for space in BlendSpace.allCases {
            XCTAssertEqual(material.composited(over: .black, in: space),
                           material.composited(over: .white, in: space))
            XCTAssertEqual(material.composited(over: .black, in: space), material.tint)
        }
        XCTAssertEqual(material.cededFraction, 0.0)
    }

    func testFullyTransparentMaterialIsTheBackdrop() {
        let material = Material(tint: .white, opacity: 0.0)
        XCTAssertEqual(material.cededFraction, 1.0)
        for space in BlendSpace.allCases {
            let backdrop = SRGBColor(hex: 0x1E6F3C)
            let result = material.composited(over: backdrop, in: space)
            XCTAssertEqual(result.red, backdrop.red, accuracy: 1e-9)
            XCTAssertEqual(result.green, backdrop.green, accuracy: 1e-9)
            XCTAssertEqual(result.blue, backdrop.blue, accuracy: 1e-9)
        }
    }

    func testOpacityIsClamped() {
        XCTAssertEqual(Material(tint: .white, opacity: 9.0).opacity, 1.0)
        XCTAssertEqual(Material(tint: .white, opacity: -3.0).opacity, 0.0)
        XCTAssertEqual(Material(tint: .white, opacity: .nan).opacity, 1.0)
    }

    /// The two blend spaces are genuinely different functions, which is why the
    /// audit refuses to pick one for you.
    func testBlendSpacesDisagreeOnTheSameInputs() {
        let material = SampleChrome.lightGlass
        let gamma = material.composited(over: .black, in: .gammaEncoded)
        let linear = material.composited(over: .black, in: .linearLight)
        XCTAssertNotEqual(gamma, linear)
        XCTAssertGreaterThan(linear.relativeLuminance, gamma.relativeLuminance)
    }
}

final class BackdropEnvelopeTests: XCTestCase {

    func testEmptyEnvelopeThrows() {
        XCTAssertThrowsError(try BackdropEnvelope(name: "empty", samples: [])) { error in
            XCTAssertEqual(error as? AuditError, .emptyEnvelope)
        }
    }

    func testSweepRejectsFewerThanTwoSamples() {
        for count in [-4, 0, 1] {
            XCTAssertThrowsError(try BackdropEnvelope.greySweep(count: count)) { error in
                XCTAssertEqual(error as? AuditError, .sweepTooSmall(requested: count))
            }
        }
    }

    func testSweepSpansBlackToWhiteInclusive() throws {
        let sweep = try BackdropEnvelope.greySweep(count: 21)
        XCTAssertEqual(sweep.samples.count, 21)
        XCTAssertEqual(sweep.samples.first, .black)
        XCTAssertEqual(sweep.samples.last, .white)
    }

    func testPhotographicEnvelopeIsNonEmpty() throws {
        XCTAssertEqual(try BackdropEnvelope.photographic().samples.count, 6)
    }
}

final class ChromeAuthorityAuditTests: XCTestCase {

    private func report(_ space: BlendSpace) throws -> AuditReport {
        try SampleChrome.audit(blendSpace: space, sweepSteps: 21)
            .evaluate(SampleChrome.surfaces)
    }

    /// Every sample surface clears its requirement against the single declared
    /// backdrop. If this ever fails, the demo is arguing the wrong thing.
    func testEverySampleSurfacePassesTheNominalCheck() throws {
        for space in BlendSpace.allCases {
            let report = try report(space)
            XCTAssertEqual(report.nominalFailures.count, 0,
                           "unexpected nominal failure in \(space.rawValue)")
        }
    }

    /// The headline finding, pinned: the same six surfaces, the same six
    /// colours, two blend spaces — five failures or three.
    func testEnvelopeFailureCountDependsOnBlendSpace() throws {
        XCTAssertEqual(try report(.gammaEncoded).envelopeFailures.count, 5)
        XCTAssertEqual(try report(.linearLight).envelopeFailures.count, 3)
    }

    /// Because every surface passes nominally, every envelope failure is by
    /// definition a silent regression.
    func testAllEnvelopeFailuresAreSilentRegressions() throws {
        for space in BlendSpace.allCases {
            let report = try report(space)
            XCTAssertEqual(report.silentRegressions.count,
                           report.envelopeFailures.count)
            XCTAssertFalse(report.passes)
        }
    }

    /// Two specific surfaces flip verdict between the blend spaces. Naming them
    /// is what makes the finding actionable rather than a statistic.
    func testTwoSurfacesFlipVerdictBetweenBlendSpaces() throws {
        let gamma = try report(.gammaEncoded)
        let linear = try report(.linearLight)

        let flipped = Set(gamma.envelopeFailures.map(\.surfaceID))
            .subtracting(linear.envelopeFailures.map(\.surfaceID))

        XCTAssertEqual(flipped, ["NavigationBar/BrandAction",
                                 "Toolbar/DestructiveAction"])
    }

    /// Nobody has to take the verdict on trust: the worst case names the exact
    /// backdrop that produced it.
    func testWorstCaseBackdropIsReproducible() throws {
        let audit = try SampleChrome.audit(blendSpace: .gammaEncoded, sweepSteps: 21)
        let surface = SampleChrome.surfaces[1]      // NavigationBar/BrandAction
        let verdict = audit.verdict(for: surface)

        let background = surface.material.composited(over: verdict.worstCaseBackdrop,
                                                     in: .gammaEncoded)
        XCTAssertEqual(background, verdict.worstCaseBackground)
        XCTAssertEqual(SRGBColor.contrastRatio(surface.foreground, background),
                       verdict.worstCaseRatio,
                       accuracy: 1e-12)
    }

    func testNominalRatioMatchesADirectCheckAgainstTheDeclaredBackdrop() throws {
        let audit = try SampleChrome.audit(blendSpace: .gammaEncoded, sweepSteps: 21)
        for surface in SampleChrome.surfaces {
            let background = surface.material.composited(
                over: SampleChrome.nominalBackdrop, in: .gammaEncoded)
            XCTAssertEqual(audit.verdict(for: surface).nominalRatio,
                           SRGBColor.contrastRatio(surface.foreground, background),
                           accuracy: 1e-12)
        }
    }

    /// The edge case that justifies sweeping instead of checking two endpoints:
    /// for a mid-luminance foreground the contrast minimum lies *inside* the
    /// sweep, where the composited background crosses the foreground's own
    /// luminance. A lightest-and-darkest check walks straight past it.
    func testWorstCaseCanBeInteriorToTheSweep() throws {
        let surface = SurfaceBaseline(
            id: "Test/MidLuminanceOnThinGlass",
            foreground: SRGBColor(hex: 0x8E8E93),
            material: SampleChrome.thinGlass,
            requirement: .normalText)

        let audit = try SampleChrome.audit(blendSpace: .gammaEncoded, sweepSteps: 21)
        let verdict = audit.verdict(for: surface)

        XCTAssertNotEqual(verdict.worstCaseBackdrop, .black)
        XCTAssertNotEqual(verdict.worstCaseBackdrop, .white)

        let endpoints = [SRGBColor.black, SRGBColor.white].map { backdrop in
            SRGBColor.contrastRatio(
                surface.foreground,
                surface.material.composited(over: backdrop, in: .gammaEncoded))
        }
        for endpointRatio in endpoints {
            XCTAssertLessThan(verdict.worstCaseRatio, endpointRatio)
        }
    }

    /// A denser sweep can only find an equal or worse minimum, never a better
    /// one — so sweep resolution is a cost/confidence dial, not a correctness
    /// risk.
    func testDenserSweepNeverImprovesTheWorstCase() throws {
        for surface in SampleChrome.surfaces {
            let coarse = try SampleChrome.audit(blendSpace: .gammaEncoded, sweepSteps: 5)
                .verdict(for: surface).worstCaseRatio
            let fine = try SampleChrome.audit(blendSpace: .gammaEncoded, sweepSteps: 101)
                .verdict(for: surface).worstCaseRatio
            XCTAssertLessThanOrEqual(fine, coarse + 1e-12, "\(surface.id)")
        }
    }

    /// An opaque surface is immune: the envelope result is exactly the nominal
    /// result, and there is nothing to regress.
    func testOpaqueSurfaceHasNoEnvelopeExposure() throws {
        let surface = SurfaceBaseline(
            id: "Test/OpaqueBar",
            foreground: SRGBColor(hex: 0x1C1C1E),
            material: .opaque(SRGBColor(hex: 0xF2F2F7)),
            requirement: .normalText)

        for space in BlendSpace.allCases {
            let verdict = try SampleChrome.audit(blendSpace: space, sweepSteps: 21)
                .verdict(for: surface)
            XCTAssertEqual(verdict.worstCaseRatio, verdict.nominalRatio, accuracy: 1e-12)
            XCTAssertEqual(verdict.overstatement, 0.0, accuracy: 1e-12)
            XCTAssertFalse(verdict.isSilentRegression)
        }
    }

    func testEmptySurfaceListProducesAPassingEmptyReport() throws {
        let report = try SampleChrome.audit(blendSpace: .gammaEncoded, sweepSteps: 21)
            .evaluate([])
        XCTAssertTrue(report.passes)
        XCTAssertTrue(report.verdicts.isEmpty)
        XCTAssertEqual(report.worstOverstatement, 0.0)
    }

    /// Holding the foreground fixed, a thinner material cedes more background
    /// and overstates by more. This is the controlled version of the claim —
    /// only the opacity differs.
    func testThinnerMaterialOverstatesMoreForTheSameForeground() throws {
        let foreground = SRGBColor(hex: 0x4A4A4E)
        let audit = try SampleChrome.audit(blendSpace: .gammaEncoded, sweepSteps: 21)

        let thick = audit.verdict(for: SurfaceBaseline(
            id: "Test/Thick", foreground: foreground,
            material: SampleChrome.lightGlass, requirement: .normalText))
        let thin = audit.verdict(for: SurfaceBaseline(
            id: "Test/Thin", foreground: foreground,
            material: SampleChrome.thinGlass, requirement: .normalText))

        XCTAssertEqual(thick.nominalRatio, thin.nominalRatio, accuracy: 1e-12)
        XCTAssertGreaterThan(thin.overstatement, thick.overstatement)
        XCTAssertEqual(SampleChrome.thinGlass.cededFraction, 0.5, accuracy: 1e-12)
        XCTAssertEqual(SampleChrome.lightGlass.cededFraction, 0.30, accuracy: 1e-12)
    }

    /// A caution worth pinning: the *largest* overstatement in the sample set
    /// belongs to a surface that still passes. Gap size is not risk — only the
    /// requirement decides that, which is why the gate keys on the threshold
    /// and not on the delta.
    func testLargestOverstatementBelongsToASurfaceThatStillPasses() throws {
        let report = try report(.gammaEncoded)
        let worst = try XCTUnwrap(report.verdicts.max(by: { $0.overstatement < $1.overstatement }))
        XCTAssertEqual(worst.surfaceID, "NavigationBar/Title")
        XCTAssertTrue(worst.passesEnvelope)
        XCTAssertFalse(worst.isSilentRegression)
    }
}
