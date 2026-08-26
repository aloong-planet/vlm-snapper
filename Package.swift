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
        .testTarget(
            name: "VLMSnapperCoreTests",
            dependencies: ["VLMSnapperCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
