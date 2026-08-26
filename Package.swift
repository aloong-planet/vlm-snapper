// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VLMSnapper",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "VLMSnapperCore", targets: ["VLMSnapperCore"]),
        .library(name: "VLMSnapperUI", targets: ["VLMSnapperUI"]),
        .executable(
            name: "VLMSnapperUIHarness",
            targets: ["VLMSnapperUIHarness"]
        ),
    ],
    targets: [
        .target(
            name: "VLMSnapperCore",
            dependencies: ["VLMSnapperHotKeyShim"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .target(
            name: "VLMSnapperHotKeyShim",
            path: "Sources/VLMSnapperHotKeyShim",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        ),
        .target(
            name: "VLMSnapperUI",
            dependencies: ["VLMSnapperCore"],
            path: "VLMSnapper",
            sources: ["UI"],
            resources: [.process("Resources/Localization")]
        ),
        .executableTarget(
            name: "VLMSnapperUIHarness",
            dependencies: ["VLMSnapperCore", "VLMSnapperUI"]
        ),
        .testTarget(
            name: "VLMSnapperCoreTests",
            dependencies: ["VLMSnapperCore"]
        ),
        .testTarget(
            name: "VLMSnapperUITests",
            dependencies: ["VLMSnapperCore", "VLMSnapperUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
