// swift-tools-version: 6.2
// Nucleon Transfer — SPM harness for the offline Core test suite.
// The app itself builds with Xcode; this package only compiles Core/ (pure
// Foundation) so contributors can run `swift test` without Xcode schemes.
import PackageDescription

let package = Package(
    name: "NucleonTransferCore",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "NucleonTransfer",                         // matches @testable import
            path: "NucleonTransfer/NucleonTransfer/Core"
        ),
        .testTarget(
            name: "NucleonTransferTests",
            dependencies: ["NucleonTransfer"],
            path: "NucleonTransfer/NucleonTransferTests"
        ),
    ]
)
