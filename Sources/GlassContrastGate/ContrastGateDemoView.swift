// The demo view is iOS-only on purpose. `canImport(SwiftUI)` alone is true on
// macOS too, and this view uses iOS-only modifiers such as
// `navigationBarTitleDisplayMode`, so a macOS `swift test` would fail to
// compile a file it has no reason to build. The audit maths below it is
// platform-agnostic and always compiles.
#if canImport(SwiftUI) && os(iOS)
import Foundation
import SwiftUI

extension SRGBColor {
    /// Bridges the audit's colour model into SwiftUI without letting SwiftUI's
    /// colour type leak back into the maths.
    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X",
               Int((red * 255).rounded()),
               Int((green * 255).rounded()),
               Int((blue * 255).rounded()))
    }
}

/// The demo the article describes: drag the backdrop under a translucent bar
/// and watch a contrast ratio that passed review fall through its threshold.
public struct ContrastGateDemoView: View {

    @State private var backdropLevel: Double = 0.0
    @State private var blendSpace: BlendSpace = .gammaEncoded

    private let surfaces = SampleChrome.surfaces
    private let sweepSteps = 21

    public init() {}

    private var backdrop: SRGBColor { .grey(backdropLevel) }

    private var report: AuditReport {
        // `greySweep(count:)` throws only for count < 2; 21 is a compile-time
        // constant, so the fallback is unreachable — but it is a fallback
        // rather than a `try!`, because a demo that can crash is not a demo.
        guard let audit = try? SampleChrome.audit(blendSpace: blendSpace,
                                                  sweepSteps: sweepSteps) else {
            return AuditReport(verdicts: [], blendSpace: blendSpace, envelopeName: "unavailable")
        }
        return audit.evaluate(surfaces)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    liveBar
                    controls
                    summary
                    surfaceList
                }
                .padding()
            }
            .navigationTitle("Chrome Authority Audit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Live bar

    private var liveBar: some View {
        VStack(spacing: 0) {
            ZStack {
                backdrop.swiftUIColor
                Text("live content behind the bar")
                    .font(.caption)
                    .foregroundStyle(backdropLevel > 0.5 ? .black : .white)
                    .opacity(0.55)
            }
            .frame(height: 74)

            ZStack {
                composited(SampleChrome.lightGlass).swiftUIColor
                HStack {
                    Text("Library")
                        .font(.headline)
                        .foregroundStyle(SRGBColor(hex: 0x1C1C1E).swiftUIColor)
                    Spacer()
                    Text("Edit")
                        .font(.body)
                        .foregroundStyle(SRGBColor(hex: 0x0051B8).swiftUIColor)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 52)

            ZStack {
                backdrop.swiftUIColor
            }
            .frame(height: 24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Simulated translucent navigation bar over a backdrop at "
                            + "\(Int(backdropLevel * 100)) percent brightness")
    }

    private func composited(_ material: Material) -> SRGBColor {
        material.composited(over: backdrop, in: blendSpace)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Blend space", selection: $blendSpace) {
                Text("Gamma-encoded").tag(BlendSpace.gammaEncoded)
                Text("Linear light").tag(BlendSpace.linearLight)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text("Backdrop \(backdrop.hexString) · composited "
                     + "\(composited(SampleChrome.lightGlass).hexString)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Slider(value: $backdropLevel, in: 0...1)
                    .accessibilityLabel("Backdrop brightness")
            }

            liveRatioRow
        }
    }

    private var liveRatioRow: some View {
        let brandAction = surfaces[1]
        let background = composited(brandAction.material)
        let ratio = SRGBColor.contrastRatio(brandAction.foreground, background)
        let required = brandAction.requirement.minimumRatio
        let passes = ratio >= required

        return HStack {
            Text("NavigationBar/BrandAction")
                .font(.caption)
            Spacer()
            Text(String(format: "%.2f:1", ratio))
                .font(.caption.monospaced().bold())
            Text(passes ? "PASS" : "FAIL")
                .font(.caption2.bold())
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(passes ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .foregroundStyle(passes ? .green : .red)
                .clipShape(Capsule())
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Brand action contrast "
                            + String(format: "%.2f to 1", ratio)
                            + ", requirement \(required) to 1, "
                            + (passes ? "passing" : "failing"))
    }

    // MARK: - Summary

    private var summary: some View {
        let current = report
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(current.envelopeFailures.count) of \(current.verdicts.count) surfaces fail "
                 + "against the envelope")
                .font(.subheadline.bold())
            Text("All \(current.verdicts.count) pass against the single declared backdrop "
                 + "\(SampleChrome.nominalBackdrop.hexString). Envelope: \(current.envelopeName).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Surface list

    private var surfaceList: some View {
        VStack(spacing: 8) {
            ForEach(report.verdicts, id: \.surfaceID) { verdict in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verdict.surfaceID)
                            .font(.caption.bold())
                        Spacer()
                        if verdict.isSilentRegression {
                            Text("SILENT REGRESSION")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.22))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(String(format: "claimed %.2f:1  ·  actual %.2f:1  ·  needs %.1f:1",
                                verdict.nominalRatio,
                                verdict.worstCaseRatio,
                                verdict.requiredRatio))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Text("worst at backdrop \(verdict.worstCaseBackdrop.hexString) "
                         + "→ background \(verdict.worstCaseBackground.hexString)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview {
    ContrastGateDemoView()
}
#endif
