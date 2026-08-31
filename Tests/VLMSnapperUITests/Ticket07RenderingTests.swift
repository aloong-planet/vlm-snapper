import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Ticket 07 UI rendering")
@MainActor
struct Ticket07RenderingTests {
    @Test("confirmed entry surfaces render in light and dark appearances")
    func confirmedSurfacesRender() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vlmsnapper-ticket07-renders", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        for appearance in RenderAppearance.allCases {
            let suffix = appearance.rawValue
            try render(
                OnboardingView(
                    snapshot: OnboardingSession(
                        permission: .ready,
                        provider: .pendingModel(.deepSeek)
                    ).snapshot,
                    onConfigurePermission: {},
                    onConfigureProvider: {},
                    onViewPrivacy: {},
                    onStart: {},
                    onFinishLater: {}
                ),
                size: CGSize(width: 680, height: 620),
                appearance: appearance,
                outputURL: outputDirectory.appendingPathComponent("onboarding-\(suffix).png")
            )
            try render(
                ProviderSetupView(
                    snapshot: ProviderSetupSnapshot(
                        selectedProvider: .deepSeek,
                        availableModelIDs: [
                            "deepseek-v4-flash-vision-exp",
                            "deepseek-vl2",
                        ],
                        selectedModelID: "deepseek-v4-flash-vision-exp",
                        phase: .ready,
                        failure: nil
                    ),
                    apiKey: .constant(""),
                    pendingModelID: .constant("deepseek-v4-flash-vision-exp"),
                    onSelectProvider: { _ in },
                    onValidate: {},
                    onRefresh: {},
                    onSelectModel: { _ in },
                    onCancel: {},
                    onDone: {}
                ),
                size: CGSize(width: 820, height: 640),
                appearance: appearance,
                outputURL: outputDirectory.appendingPathComponent("provider-\(suffix).png")
            )
            try render(
                ScreenCapturePermissionRecoveryView(
                    state: .unavailable,
                    onPrimaryAction: {},
                    onDismiss: {}
                ),
                size: CGSize(width: 470, height: 220),
                appearance: appearance,
                outputURL: outputDirectory.appendingPathComponent("permission-\(suffix).png")
            )
            try render(
                MenuBarContainerView(
                    recentItems: [
                        MenuRecentItem(
                            id: "1",
                            title: "Designing Calm Software",
                            detail: "DeepSeek · Translate"
                        ),
                    ],
                    permission: .ready,
                    provider: .ready(
                        provider: .deepSeek,
                        modelID: "deepseek-v4-flash-vision-exp"
                    ),
                    providerSnapshot: ProviderSetupSnapshot(
                        selectedProvider: .deepSeek,
                        availableModelIDs: ["deepseek-v4-flash-vision-exp"],
                        selectedModelID: "deepseek-v4-flash-vision-exp",
                        phase: .ready,
                        failure: nil
                    ),
                    apiKey: .constant(""),
                    pendingModelID: .constant("deepseek-v4-flash-vision-exp"),
                    callbacks: MenuBarCallbacks(
                        onCapture: {},
                        onPermissionPrimaryAction: {},
                        onSelectProvider: { _ in },
                        onValidateProvider: {},
                        onRefreshModels: {},
                        onSelectModel: { _ in },
                        onProviderDone: {},
                        onOpenRecent: { _ in },
                        onNavigate: { _ in },
                        onCheckUpdates: {}
                    )
                ),
                size: CGSize(width: 330, height: 330),
                appearance: appearance,
                outputURL: outputDirectory.appendingPathComponent("menu-\(suffix).png")
            )
            try render(
                StoragePrivacyDetailView(onClose: {}),
                size: CGSize(width: 620, height: 520),
                appearance: appearance,
                outputURL: outputDirectory.appendingPathComponent("privacy-\(suffix).png")
            )
        }

        let renderedFiles = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }
        #expect(renderedFiles.count == 10)
    }

    private func render<Content: View>(
        _ content: Content,
        size: CGSize,
        appearance: RenderAppearance,
        outputURL: URL
    ) throws {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: appearance.nsAppearanceName)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let representation = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let png = try #require(representation.representation(using: .png, properties: [:]))
        #expect(representation.pixelsWide == Int(size.width * window.backingScaleFactor))
        #expect(representation.pixelsHigh == Int(size.height * window.backingScaleFactor))
        #expect(png.count > 10_000)
        try png.write(to: outputURL, options: .atomic)
    }
}

private enum RenderAppearance: String, CaseIterable {
    case light
    case dark

    var nsAppearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
