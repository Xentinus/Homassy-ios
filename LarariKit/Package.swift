// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LarariKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LarariCore", targets: ["LarariCore"]),
        // Linked by the app and by the widget extension (N-04). No dependencies, no resources.
        .library(name: "LarariShared", targets: ["LarariShared"]),
    ],
    dependencies: [
        // The only third-party dependency of the project (MIT). Used for .larari archives.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(name: "LarariShared"),
        .target(
            name: "LarariCore",
            dependencies: ["LarariShared", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "LarariSharedTests", dependencies: ["LarariShared"]),
        .testTarget(
            name: "LarariCoreTests",
            dependencies: ["LarariCore", "LarariShared", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
