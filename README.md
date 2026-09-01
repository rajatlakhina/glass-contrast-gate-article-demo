# GlassContrastGate

**A contrast gate for chrome your app no longer fully owns.**

Under iOS 26 the `UIDesignRequiresCompatibility` Info.plist flag bought teams a year of the
pre-Liquid-Glass look. Under the iOS 27 SDK it is reportedly ignored: recompile and the design
applies. That report is second-hand — [AppleInsider](https://appleinsider.com/articles/26/03/26/stop-holding-out-hope-liquid-glass-will-be-mandatory-in-ios-27)
relaying an account of an Apple developer workshop — and Apple has published nothing on it, so
treat the timing as likely rather than settled. The engineering problem below does not depend on
the date.

The part that gets filed as a design project is not a design project. When standard chrome becomes
translucent, the app stops owning its own background — the system composites the app's material
over whatever content happens to be underneath. Every accessibility check that measured a
foreground against *one declared background colour* is now measuring against an assumption that no
longer holds.

`GlassContrastGate` is the smallest honest version of the check that replaces it: evaluate contrast
across the **range** of backdrops a surface can sit on, and report the worst case with the exact
backdrop that produced it.

---

## The finding

Six chrome surfaces, coloured the way a competent design system would have coloured them. **All six
pass** the conventional check against the declared bar colour `#F2F2F7`. Then the same six are
swept across 21 backdrop levels behind the same material:

| Surface | Needs | Claimed | Actual (gamma-encoded) | Actual (linear light) |
|---|---|---|---|---|
| `NavigationBar/Title` | 3.0:1 | 15.25:1 | 7.29:1 | 10.92:1 |
| `NavigationBar/BrandAction` | 4.5:1 | 6.56:1 | **3.14:1** | 4.70:1 |
| `Toolbar/SecondaryLabel` | 4.5:1 | 4.69:1 | **2.24:1** | **3.35:1** |
| `TabBar/SelectedIcon` | 3.0:1 | 3.60:1 | **1.72:1** | **2.58:1** |
| `SearchField/Placeholder` | 4.5:1 | 7.91:1 | **2.03:1** | **4.16:1** |
| `Toolbar/DestructiveAction` | 4.5:1 | 6.44:1 | **3.08:1** | 4.61:1 |

**5 of 6 fail under gamma-encoded blending. 3 of 6 fail under linear light.** `NavigationBar/BrandAction`
and `Toolbar/DestructiveAction` flip verdict on the blend space alone — same colour, same material,
same requirement, opposite answers.

That is why `BlendSpace` is a required parameter with no default. A library cannot know which of
the two your platform uses, and guessing on your behalf would bury the one input that changes the
verdict. Measure it on a device, then pass it in.

Note also what the material here is: a **flat alpha tint**, not a simulation of Liquid Glass. Real
system materials blur, adapt their tint to content, and apply vibrancy. This models only the part
that changed structurally — that some fraction of the background is now content the app does not
control.

---

## Using it

```swift
import GlassContrastGate

let audit = ChromeAuthorityAudit(
    nominalBackdrop: SRGBColor(hex: 0xF2F2F7),
    envelope: try BackdropEnvelope.greySweep(count: 21),
    blendSpace: .gammaEncoded)

let report = audit.evaluate([
    SurfaceBaseline(
        id: "NavigationBar/BrandAction",
        foreground: SRGBColor(hex: 0x0051B8),
        material: Material(tint: SRGBColor(hex: 0xF2F2F7), opacity: 0.70),
        requirement: .normalText)
])

for verdict in report.silentRegressions {
    print(verdict.surfaceID,
          verdict.nominalRatio,          // 6.56 — what the old check said
          verdict.worstCaseRatio,        // 3.14 — what the model says is there
          verdict.worstCaseBackdrop)     // #000000 — go reproduce it
}
```

`report.passes` is the gate. Wire it into CI and a regression stops being something someone has to
notice by eye.

### The variable that matters

```swift
public var cededFraction: Double { 1.0 - opacity }
```

Opacity is the share of the background the app still controls. `1 - opacity` is the share it has
handed to whatever scrolls underneath. At `opacity == 1.0` the backdrop cannot move the result at
all, and `testOpaqueSurfaceHasNoEnvelopeExposure` pins that: worst case equals nominal, exactly.

---

## What's in it

- **`SRGBColor`** — WCAG 2.1 relative luminance and contrast ratio. Channels clamp rather than
  trap, because an audit that crashes on a malformed design token is an audit nobody runs in CI.
- **`Material`** — tint plus opacity, composited over a backdrop in an explicit `BlendSpace`. The
  two degenerate opacities are answered exactly rather than through a transfer-function round trip
  that costs a bit of precision.
- **`BackdropEnvelope`** — the set of backdrops a surface must survive. `init` **throws** on an
  empty sample set; silently returning the nominal value would be the exact lie the library exists
  to catch.
- **`SurfaceBaseline`** / **`ContrastRequirement`** — a named surface and the WCAG minimum it claims.
- **`ChromeAuthorityAudit`** → **`AuditReport`** — nominal vs. worst case per surface, plus
  `isSilentRegression` for the defect class that matters: passed for years, fails now, nobody
  touched it.

### Why a sweep and not two endpoints

`testWorstCaseCanBeInteriorToTheSweep` pins a case a lightest-and-darkest check walks straight past.
For a mid-luminance foreground (`#8E8E93`) on the 50%-opacity material, **under gamma-encoded
blending**, contrast bottoms out at **1.03:1** at backdrop `#262626` — while the black endpoint
reads 1.33:1 and the white endpoint 3.09:1. The minimum sits where the composited background
crosses the foreground's own luminance.

Two honest limits on that finding. Under linear-light blending the same surface bottoms out at the
black endpoint, so a two-point check would catch it. And in the six-surface inventory above every
worst case lands at the dark end in both spaces. The interior minimum is a real trap, not a common
one — which is the argument for sweeping rather than for trusting a rule of thumb about where to
look.

`testDenserSweepNeverImprovesTheWorstCase` pins the companion property: resolution is a
cost/confidence dial, never a correctness risk.

---

## Verification status

**Honest, and please read it before trusting the screenshots section — there isn't one.**

- `swift build` — **clean**, Swift 6.0.3, Linux aarch64.
- `swift test` — **26 tests, 0 failures.**
- **The Simulator run did not happen this cycle.** This repo was produced in an automated,
  unattended session in which macOS computer-use grants cannot be approved, so Xcode could not be
  opened and `Demo.xcodeproj` was never launched on a device. There are therefore **no screenshots
  of the running app in this repo** — the diagrams in the article are drawn from `swift test`
  output, not from a device capture.
- **`ContrastGateDemoView.swift` has never been type-checked.** It sits behind
  `#if canImport(SwiftUI)`, and the Linux toolchain used above has no SwiftUI, so `swift build`
  compiled none of it. It parses cleanly (`swiftc -parse`) and that is the entire claim. The audit
  maths underneath it is fully covered; the view is not.
- `Demo.xcodeproj/project.pbxproj` was hand-authored and machine-checked instead: braces and parens
  balanced (32/32, 24/24), all 22 object ids referenced are defined, zero dangling references, the
  asset catalog JSON parses, and `Demo.xcscheme` is well-formed XML. That is a structural check, not
  a build. **If you clone this and the project does not open, that is the gap — open an issue and I
  will fix it.**
- The library carries no `iOS 27`-only API and no SwiftUI dependency in its maths, so every number
  above is reproducible with `swift test` on any platform with a Swift 6 toolchain, independent of
  Xcode. That is the part you should trust; the UI layer is the part you should check.

---

## Running the demo

```
git clone https://github.com/rajatlakhina/glass-contrast-gate-article-demo.git
cd glass-contrast-gate-article-demo
swift test                 # 26 tests — the numbers above, reproducible
open Demo.xcodeproj        # pick any iOS Simulator, Build & Run
```

No second repo, no package resolution over the network — `Demo.xcodeproj` consumes the library
through an `XCLocalSwiftPackageReference` pointing at this same directory.

The demo app puts a translucent bar over a backdrop you can drag from black to white, flips between
the two blend spaces, and shows the audit's verdict for all six surfaces updating live.

---

Article: *(added after publish)*

MIT licensed.
