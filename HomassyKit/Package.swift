// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomassyKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HomassyCore", targets: ["HomassyCore"]),
        // Linked by the app and by the widget extension (N-04). No dependencies, no resources.
        .library(name: "HomassyShared", targets: ["HomassyShared"]),
    ],
    dependencies: [
        // The only third-party dependency of the project (MIT). Used for .homassy archives.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(name: "HomassyShared"),
        .target(
            name: "HomassyCore",
            dependencies: ["HomassyShared", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "HomassySharedTests", dependencies: ["HomassyShared"]),
        .testTarget(
            name: "HomassyCoreTests",
            dependencies: ["HomassyCore", "HomassyShared", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
