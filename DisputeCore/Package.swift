// swift-tools-version:6.0
import PackageDescription

// DisputeCore holds every model type, business rule and engine, with no UI
// dependency, so the app's logic stays unit-testable without launching a
// simulator.
//
// There used to be a second target, `DisputeLlama`, holding llama.cpp and the
// engine that ran a downloaded model on the phone. It is gone, along with the
// 31 MB xcframework it vendored — see docs/DECISIONS.md. Everything now runs
// through `CloudEngine`, which is an HTTP client, so this package links no
// binaries and builds with the command line tools alone.
let package = Package(
    name: "DisputeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DisputeCore", targets: ["DisputeCore"]),
    ],
    targets: [
        .target(name: "DisputeCore"),
        .testTarget(name: "DisputeCoreTests", dependencies: ["DisputeCore"]),
    ]
)
