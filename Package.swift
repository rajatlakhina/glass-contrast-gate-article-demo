// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlassContrastGate",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GlassContrastGate", targets: ["GlassContrastGate"])
    ],
    targets: [
        .target(name: "GlassContrastGate"),
        .testTarget(name: "GlassContrastGateTests", dependencies: ["GlassContrastGate"])
    ]
)
