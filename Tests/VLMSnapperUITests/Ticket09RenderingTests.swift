import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Ticket 09 UI rendering", .serialized)
@MainActor
struct Ticket09RenderingTests {
    @Test("configured localization bundle changes visible strings")
    func configuredLocalizationChangesStrings() {
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        #expect(VLMSnapperStrings.updateAutomaticChecks == "Automatically Check for Updates")
        VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
        #expect(
            VLMSnapperStrings.updateAutomaticChecks
                == "\u{81EA}\u{52A8}\u{68C0}\u{67E5}\u{66F4}\u{65B0}"
        )
    }

    @Test("menu and General Settings render updater callback states")
    func updaterStatesRender() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "vlmsnapper-ticket09-renders-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let version = AvailableUpdateVersion(version: "1.1.0", displayVersion: "1.1.0")
        let states: [UpdateLifecycleState] = [
            .available(version),
            .downloading(version, receivedBytes: 500, expectedBytes: 1_000),
            .readyToInstall(version),
            .failed(.check, code: "updater_failed"),
        ]

        for language in Ticket09Language.allCases {
            VLMSnapperLocalization.configure(effectiveLanguage: language.effectiveLanguage)
            for appearance in Ticket09Appearance.allCases {
                for (index, state) in states.enumerated() {
                    let suffix = "\(language.rawValue)-\(appearance.rawValue)-\(index)"
                    try render(
                        MenuBarPanelView(
                            recentItems: [],
                            updateState: state,
                            onCapture: {},
                            onOpenRecent: { _ in },
                            onNavigate: { _ in },
                            onCheckUpdates: {},
                            onDownloadUpdate: {},
                            onQuit: {}
                        ),
                        size: CGSize(width: 330, height: 390),
                        appearance: appearance,
                        outputURL: outputDirectory.appendingPathComponent("menu-\(suffix).png")
                    )
                    try render(
                        ManagementCenterView(
                            destination: .settings,
                            records: [],
                            settings: GeneralSettingsSnapshot(
                                languageRestartRequired: index == 2,
                                updateState: state
                            )
                        ),
                        size: CGSize(width: 1080, height: 700),
                        appearance: appearance,
                        outputURL: outputDirectory.appendingPathComponent("settings-\(suffix).png")
                    )
                }
            }
        }

        let renderedFiles = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }
        #expect(renderedFiles.count == 32)
    }

    private func render<Content: View>(
        _ content: Content,
        size: CGSize,
        appearance: Ticket09Appearance,
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
        let representation = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let png = try #require(representation.representation(using: .png, properties: [:]))
        #expect(png.count > 10_000)
        try png.write(to: outputURL, options: .atomic)
    }
}

private enum Ticket09Language: String, CaseIterable {
    case zhHans
    case en

    var effectiveLanguage: EffectiveApplicationLanguage {
        switch self {
        case .zhHans: .simplifiedChinese
        case .en: .english
        }
    }
}

private enum Ticket09Appearance: String, CaseIterable {
    case light
    case dark

    var nsAppearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
