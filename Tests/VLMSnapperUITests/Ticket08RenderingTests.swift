import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Ticket 08 UI rendering")
@MainActor
struct Ticket08RenderingTests {
    @Test("management center states render in light and dark appearances")
    func managementCenterStatesRender() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vlmsnapper-ticket08-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let records = sampleRecords

        for appearance in Ticket08Appearance.allCases {
            let suffix = appearance.rawValue
            try render(
                ManagementCenterView(
                    destination: .history,
                    records: records,
                    selectedRecordID: records.first?.id,
                    selectedImage: sampleImage
                ),
                appearance: appearance,
                outputURL: outputDirectory.appendingPathComponent("history-\(suffix).png")
            )
            try render(
                ManagementCenterView(destination: .settings, records: records),
                appearance: appearance,
                outputURL: outputDirectory.appendingPathComponent("settings-\(suffix).png")
            )
            try render(
                ManagementCenterView(destination: .history, records: records, searchText: "no-match"),
                appearance: appearance,
                outputURL: outputDirectory.appendingPathComponent("empty-\(suffix).png")
            )
            try render(
                ManagementCenterView(destination: .history, records: records, cleanupFailureCount: 2),
                appearance: appearance,
                outputURL: outputDirectory.appendingPathComponent("cleanup-failure-\(suffix).png")
            )
        }

        let renderedFiles = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }
        #expect(renderedFiles.count == 8)
    }

    private var sampleRecords: [HistoryRecord] {
        [
            record(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                kind: .translate,
                source: "Designing Calm Software",
                translation: "Excellent utility software stays close to the task.",
                pinned: true
            ),
            record(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                kind: .extract,
                source: "Vision API integration guide",
                translation: nil,
                pinned: false
            ),
        ]
    }

    private func record(
        id: UUID,
        kind: PersistedOperationKind,
        source: String,
        translation: String?,
        pinned: Bool
    ) -> HistoryRecord {
        HistoryRecord(
            operation: StoredOperation(
                id: id,
                screenshot: ManagedScreenshot(path: "/Pictures/\(id).png", sha256: "sha"),
                selection: ProviderSelection(providerID: "DeepSeek", modelID: "deepseek-v4-flash-vision-exp"),
                status: .succeeded,
                sourceMarkdown: source,
                translationMarkdown: translation,
                kind: kind,
                targetLanguage: kind == .translate ? "zh-Hans" : nil
            ),
            createdAt: Date(timeIntervalSince1970: 1_787_725_812),
            isPinned: pinned,
            metrics: PersistedOperationMetrics(
                firstTextLatencyMilliseconds: 430,
                totalLatencyMilliseconds: 1_280,
                usage: ProviderTokenUsage(inputTokens: 124, outputTokens: 38, totalTokens: 162)
            )
        )
    }

    private var sampleImage: NSImage {
        NSImage(size: NSSize(width: 640, height: 260), flipped: false) { rect in
            NSColor.controlBackgroundColor.setFill()
            rect.fill()
            "Designing Calm Software".draw(
                at: NSPoint(x: 36, y: 150),
                withAttributes: [.font: NSFont.systemFont(ofSize: 32, weight: .bold)]
            )
            return true
        }
    }

    private func render<Content: View>(
        _ content: Content,
        appearance: Ticket08Appearance,
        outputURL: URL
    ) throws {
        let size = CGSize(width: 1080, height: 700)
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
        #expect(png.count > 20_000)
        try png.write(to: outputURL, options: .atomic)
    }
}

private enum Ticket08Appearance: String, CaseIterable {
    case light
    case dark

    var nsAppearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
