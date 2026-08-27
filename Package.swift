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
        .library(name: "VLMSnapperSparkle", targets: ["VLMSnapperSparkle"]),
        .library(name: "VLMSnapperUI", targets: ["VLMSnapperUI"]),
        .executable(name: "VLMSnapperApp", targets: ["VLMSnapperApp"]),
        .executable(
            name: "VLMSnapperLiveProviderGate",
            targets: ["VLMSnapperLiveProviderGate"]
        ),
        .executable(
            name: "VLMSnapperUIHarness",
            targets: ["VLMSnapperUIHarness"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.6"
        ),
    ],
    targets: [
        .target(
            name: "VLMSnapperCore",
            dependencies: ["VLMSnapperHotKeyShim", "VLMSnapperProcessShim"],
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
            name: "VLMSnapperProcessShim",
            path: "Sources/VLMSnapperProcessShim",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "VLMSnapperUI",
            dependencies: ["VLMSnapperCore"],
            path: "VLMSnapper",
            sources: ["UI"],
            resources: [.process("Resources/Localization")]
        ),
        .target(
            name: "VLMSnapperSparkle",
            dependencies: [
                "VLMSnapperCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "VLMSnapperApp",
            dependencies: [
                "VLMSnapperCore",
                "VLMSnapperSparkle",
                "VLMSnapperUI",
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(
            name: "VLMSnapperUIHarness",
            dependencies: ["VLMSnapperCore", "VLMSnapperUI"]
        ),
        .executableTarget(
            name: "VLMSnapperLiveProviderGate",
            dependencies: ["VLMSnapperCore"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .testTarget(
            name: "VLMSnapperCoreTests",
            dependencies: ["VLMSnapperCore"]
        ),
        .testTarget(
            name: "VLMSnapperUITests",
            dependencies: ["VLMSnapperCore", "VLMSnapperUI"]
        ),
        .testTarget(
            name: "VLMSnapperSparkleTests",
            dependencies: ["VLMSnapperCore", "VLMSnapperSparkle"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
