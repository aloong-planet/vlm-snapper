import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Ticket 10 UI rendering", .serialized)
@MainActor
struct Ticket10RenderingTests {
    @Test("production toolbar renders localized target-language selection")
    func toolbarRendersTargetLanguageSelection() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "vlmsnapper-ticket10-renders-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        for language in Ticket10Language.allCases {
            VLMSnapperLocalization.configure(
                effectiveLanguage: language.effectiveLanguage
            )
            for appearance in Ticket10Appearance.allCases {
                try renderToolbar(
                    language: language,
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent(
                        "toolbar-\(language.rawValue)-\(appearance.rawValue).png"
                    )
                )
            }
        }

        let renderedFiles = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }
        #expect(renderedFiles.count == 4)
        #expect(
            GlobalShortcutDisplayFormatter.string(for: .defaultCapture)
                == "⌥⇧S"
        )
    }

    private func renderToolbar(
        language: Ticket10Language,
        appearance: Ticket10Appearance,
        outputURL: URL
    ) throws {
        var operation = WorkspaceOperationKind.translate
        var targetLanguageCode = "zh-Hans"
        let view = CaptureOperationToolbar(
            operation: Binding(get: { operation }, set: { operation = $0 }),
            targetLanguageCode: Binding(
                get: { targetLanguageCode },
                set: { targetLanguageCode = $0 }
            ),
            targetLanguages: [
                TargetLanguageOption(
                    code: "zh-Hans",
                    name: language == .zhHans
                        ? "\u{7B80}\u{4F53}\u{4E2D}\u{6587}"
                        : "Simplified Chinese"
                ),
                TargetLanguageOption(code: "en", name: "English"),
            ],
            providerSummary: "DeepSeek · deepseek-v4-flash-vision-exp",
            onStart: { _ in },
            onCancel: {}
        )
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: appearance.nsAppearanceName)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let representation = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let png = try #require(
            representation.representation(using: .png, properties: [:])
        )
        #expect(png.count > 5_000)
        try png.write(to: outputURL, options: .atomic)
    }
}

private enum Ticket10Language: String, CaseIterable {
    case zhHans
    case en

    var effectiveLanguage: EffectiveApplicationLanguage {
        self == .zhHans ? .simplifiedChinese : .english
    }
}

private enum Ticket10Appearance: String, CaseIterable {
    case light
    case dark

    var nsAppearanceName: NSAppearance.Name {
        self == .light ? .aqua : .darkAqua
    }
}
