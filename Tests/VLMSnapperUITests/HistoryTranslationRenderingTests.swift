import AppKit
import SwiftUI
import XCTest
import VLMSnapperCore
@testable import VLMSnapperUI

// Production view rendering and text selection, not physical input or live-model evidence.
@MainActor
final class HistoryTranslationRenderingTests: XCTestCase {
    func testConversionRendersFullSourceAndAlignedTranslationInBothThemes() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vlmsnapper-text-conversion-renders")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let record = HistoryRecord(operation: StoredOperation(id: UUID(),
            screenshot: ManagedScreenshot(path: "/missing.png", sha256: "fixture"),
            selection: ProviderSelection(providerID: "deepseek", modelID: "fixture-model"), status: .succeeded,
            sourceMarkdown: "Need help? Contact us."), createdAt: Date(timeIntervalSince1970: 1_800_000_000), isPinned: true)
        let presentation = HistoryRetryPresentation()
        presentation.allowsStart = true
        let plan = try SavedTextTranslation(source: "Need help? Contact us.")
        for language in [EffectiveApplicationLanguage.simplifiedChinese, .english] {
            VLMSnapperLocalization.configure(effectiveLanguage: language)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let host = NSHostingView(rootView: ManagementCenterView(destination: .history,
                    records: [record], selectedRecordID: record.id, selectedImageLoadFailed: true,
                    callbacks: ManagementCenterCallbacks(historyRetry: presentation)))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }
                presentation.recordID = record.id
                presentation.originalSource = "Need help? Contact us."
                presentation.isTextConversion = true
                presentation.isRunning = true
                presentation.slot = WorkspaceOperationSlot(attempt: .preparing)
                XCTAssertTrue(waitForNativeCondition(timeout: 2) {
                    host.layoutSubtreeIfNeeded()
                    return self.textViews(host).count == 2
                })
                XCTAssertEqual(textViews(host).first?.string, "Need help? Contact us.")
                XCTAssertEqual(textViews(host).last?.string, "")
                let segments = try plan.merging([
                    TranslationSegment(id: "saved-1", block: "saved", kind: .paragraph,
                        source: "Need help? ", translation: "需要帮助？")
                ], complete: false)
                presentation.slot = WorkspaceOperationSlot(attempt: .streaming, sourceDelta: "Need help? Contact us.",
                    translationDelta: "需要帮助？", segments: segments)
                XCTAssertTrue(waitForNativeCondition(timeout: 2) {
                    host.layoutSubtreeIfNeeded()
                    return self.textViews(host).last?.string == "需要帮助？"
                })
                let source = try XCTUnwrap(textViews(host).first)
                let target = try XCTUnwrap(textViews(host).last)
                XCTAssertEqual(source.string, "Need help? Contact us.")
                XCTAssertEqual(source.frame.width, target.frame.width, accuracy: 1)
                source.setSelectedRange(NSRange(location: 0, length: 10))
                XCTAssertNotNil(target.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil))
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: root.appendingPathComponent("\(language)-\(appearance.rawValue).png"))
                window.close()
            }
        }
        print("Text conversion render evidence: \(root.path)")
    }

    private func textViews(_ view: NSView) -> [NSTextView] {
        ([view] + descendants(view)).compactMap { $0 as? NSTextView }.filter { $0.isSelectable && !$0.isEditable }
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
