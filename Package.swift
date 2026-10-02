// swift-tools-version: 6.2
// Neutron Transfer — SPM harness for the offline Core test suite.
// The app itself builds with Xcode; this package only compiles Core/ (pure
// Foundation) so contributors can run `swift test` without Xcode schemes.
import PackageDescription

let package = Package(
    name: "NeutronTransferCore",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "NeutronTransfer",                         // matches @testable import
            path: "NeutronTransfer/NeutronTransfer/Core"
        ),
        .testTarget(
            name: "NeutronTransferTests",
            dependencies: ["NeutronTransfer"],
            path: "NeutronTransfer/NeutronTransferTests"
        ),
    ]
)
