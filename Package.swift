// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VLMSnapper",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "VLMSnapperCore", targets: ["VLMSnapperCore"]),
    ],
    targets: [
        .target(
            name: "VLMSnapperCore",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "VLMSnapperCoreTests",
            dependencies: ["VLMSnapperCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
