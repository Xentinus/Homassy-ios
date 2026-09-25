// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomassyKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HomassyCore", targets: ["HomassyCore"]),
    ],
    dependencies: [
        // The only third-party dependency of the project (MIT). Used for .homassy archives.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "HomassyCore",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HomassyCoreTests",
            dependencies: ["HomassyCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
