// swift-tools-version:5.9
// `tunl`: Tunl from the command line and for AI agents (MCP). Distributed
// through the Homebrew tap, outside the App Store, and drives the App Store
// app rather than replacing it. See cli/README.md.
import PackageDescription

let package = Package(
    name: "tunl",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "tunl", targets: ["tunl"])],
    targets: [
        .target(name: "TunlCLICore"),
        .executableTarget(name: "tunl", dependencies: ["TunlCLICore"]),
        .testTarget(name: "TunlCLICoreTests", dependencies: ["TunlCLICore"],
                    resources: [.copy("Fixtures")]),
    ]
)
