// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomassyKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HomassyCore", targets: ["HomassyCore"]),
    ],
    targets: [
        .target(name: "HomassyCore"),
        .testTarget(name: "HomassyCoreTests", dependencies: ["HomassyCore"]),
    ]
)
