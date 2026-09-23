import AppKit
import SwiftUI
import XCTest
import VLMSnapperCore
@testable import VLMSnapperUI

// Exercise the production result surface. These responder/selection tests do
// not claim physical mouse delivery or real Provider response quality.
// Long legacy content covers native geometry, not the reported installed-app
// hang; that still needs a sample captured while the fault is occurring.
@MainActor
final class BilingualResultTests: XCTestCase {
    func testMeasuringAlternativeWidthsDoesNotChangeVisibleLineWrapping() throws {
        let surface = BilingualResultContentView()
        surface.update(source: "Verified inside the zip itself: " + String(repeating: "files at the zip root, version checked. ", count: 20)
            + "\nTo publish: https://chrome.google.com/webstore/devconsole/" + String(repeating: "abcdef", count: 60),
            translation: String(repeating: "在压缩包内部验证：文件必须位于根目录。", count: 20), segments: nil, onCopy: { _ in })
        surface.frame = NSRect(x: 0, y: 0, width: 700, height: surface.height(for: 700))
        surface.layoutSubtreeIfNeeded()
        // SwiftUI may probe other candidate sizes without committing a frame.
        for proposed in [10000.0, 200.0, 1400.0] {
            _ = surface.height(for: proposed)
            let fields = descendants(surface).compactMap { $0 as? NSTextView }
            XCTAssertEqual(fields.count, 2)
            for text in fields {
                let manager = try XCTUnwrap(text.layoutManager)
                let container = try XCTUnwrap(text.textContainer)
                manager.ensureLayout(for: container)
                let rect = manager.usedRect(for: container)
                XCTAssertLessThanOrEqual(rect.maxX, text.bounds.width + 1, "Measuring must not change displayed wrapping")
                XCTAssertLessThanOrEqual(rect.maxY, text.bounds.height + 1, "Measuring must not change displayed height")
                XCTAssertGreaterThan(rect.height, 50, "Long paragraphs must wrap, not be clipped to one line")
            }
        }
    }

    func testLongLegacyHistoryKeepsEntireTextInsideBilingualSection() throws {
        let paragraph = "What shipped. The pipeline now has an entry point the desktop app can call: one command that runs a range of stages over a run directory, streams JSON-line events, and records what it did so an interrupted run continues rather than restarting. Four new modules cover preparation, the run record, the event protocol, and preflight validation. All nine acceptance items are ticked against named tests. The full suite is 131 tests including the four golden charts, bit-for-bit exact."
        let record = HistoryRecord(operation: StoredOperation(id: UUID(),
            screenshot: ManagedScreenshot(path: "/missing-fixture.png", sha256: "fixture"),
            selection: ProviderSelection(providerID: "deepseek", modelID: "fixture"), status: .succeeded,
            sourceMarkdown: paragraph, translationMarkdown: "已交付内容。流水线有了桌面应用入口。",
            kind: .translate, targetLanguage: "zh-Hans"), createdAt: Date(), isPinned: false)
        let host = NSHostingView(rootView: ManagementCenterView(destination: .history, records: [record], selectedRecordID: record.id))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.orderFront(nil)
        for width in [1200.0, 1600.0, 1000.0, 1600.0, 1000.0, 1200.0] {
            window.setContentSize(NSSize(width: width, height: 800))
            host.layoutSubtreeIfNeeded()
            let fields = descendants(host).compactMap { $0 as? NSTextView }.filter { $0.isSelectable && !$0.isEditable }
            XCTAssertEqual(fields.count, 2)
            for field in fields {
                let parent = try XCTUnwrap(field.superview)
                let manager = try XCTUnwrap(field.layoutManager)
                let container = try XCTUnwrap(field.textContainer)
                manager.ensureLayout(for: container)
                let glyphBounds = manager.usedRect(for: container).offsetBy(dx: field.textContainerOrigin.x, dy: field.textContainerOrigin.y)
                let displayed = field.convert(glyphBounds, to: parent)
                XCTAssertLessThanOrEqual(glyphBounds.maxX, field.bounds.width + 1, "Neither column may draw across its edge")
                XCTAssertGreaterThan(field.frame.width, 100)
                XCTAssertGreaterThan(glyphBounds.height, 0)
                XCTAssertLessThanOrEqual(displayed.maxY, parent.bounds.maxY + 1,
                    "Long text must fit the height reserved before metrics at window width \(width); text=\(displayed), section=\(parent.bounds)")
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vlmsnapper-long-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("history.png"))
        print("Long history render evidence: \(directory.path)")
    }

    func testStreamingColumnsReflowAndKeepLinkedSelectionAcrossWidths() throws {
        var parts = [TranslationSegment(id: "a", block: "p", kind: .paragraph,
            source: "Need help? ", translation: "需要帮助？")]
        func result() -> BilingualResultView {
            BilingualResultView(source: parts.map(\.source).joined(),
                translation: parts.map(\.translation).joined(), segments: parts)
        }
        let host = NSHostingView(rootView: result())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 1800),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        let firstSource = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        firstSource.setSelectedRange(NSRange(location: 0, length: 4))
        parts.append(TranslationSegment(id: "b", block: "p", kind: .paragraph,
            source: String(repeating: "Contact our support team. ", count: 12),
            translation: String(repeating: "请联系我们的支持团队。", count: 12)))
        host.rootView = result()
        XCTAssertTrue(waitForNativeCondition(timeout: 1) {
            host.layoutSubtreeIfNeeded()
            return firstSource.string.contains("Contact our support team.")
        })
        for width in [700.0, 1100.0, 500.0, 700.0] {
            window.setContentSize(NSSize(width: width, height: 1800))
            host.layoutSubtreeIfNeeded()
            _ = host.fittingSize
            let texts = descendants(host).compactMap { $0 as? NSTextView }
            XCTAssertEqual(texts.count, 2)
            let source = try XCTUnwrap(texts.first)
            let target = try XCTUnwrap(texts.last)
            XCTAssertEqual(source.selectedRange(), NSRange(location: 0, length: 4))
            XCTAssertNotNil(background(target, at: 0))
            XCTAssertNil(background(target, at: 5), "The appended passage is not part of the selection")
            for text in texts {
                let manager = try XCTUnwrap(text.layoutManager)
                let container = try XCTUnwrap(text.textContainer)
                manager.ensureLayout(for: container)
                let rect = manager.usedRect(for: container)
                XCTAssertLessThanOrEqual(rect.maxX, text.bounds.width + 1)
                XCTAssertLessThanOrEqual(rect.maxY, text.bounds.height + 1)
                XCTAssertEqual(NSMaxRange(manager.glyphRange(for: container)), manager.numberOfGlyphs,
                    "All glyphs must be laid out, not hidden by clipping")
            }
        }
    }

    func testProductionResultUsesIndependentSelectableColumns() throws {
        let result = WorkspaceCommittedResult(sourceMarkdown: "Need help? Contact us.",
            translationMarkdown: "需要帮助？联系我们。", segments: [
                TranslationSegment(id: "a", block: "p1", kind: .paragraph, source: "Need help? ", translation: "需要帮助？"),
                TranslationSegment(id: "b", block: "p1", kind: .paragraph, source: "Contact us.", translation: "联系我们。"),
            ])
        let view = ResultWorkspaceView(operation: .constant(.translate),
            snapshot: OperationWorkspaceSnapshot(selectedOperation: .translate, extract: WorkspaceOperationSlot(),
                translate: WorkspaceOperationSlot(attempt: .succeeded, committedResult: result)),
            originalImage: nil, providerSummary: "Fixture", targetLanguage: "zh-Hans", onStart: { _ in },
            onCopy: { _ in }, onRetrySave: {})
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        let fields = descendants(host).compactMap { $0 as? NSTextView }
        XCTAssertEqual(fields.count, 2, "Each language must support independent continuous native selection")
        guard fields.count == 2 else { return }
        XCTAssertEqual(fields[0].string, "Need help? Contact us.")
        XCTAssertEqual(fields[1].string, "需要帮助？联系我们。")
        let first = fields[0].convert(fields[0].bounds, to: host)
        let second = fields[1].convert(fields[1].bounds, to: host)
        XCTAssertEqual(first.minY, second.minY, accuracy: 1)
        XCTAssertGreaterThan(second.minX, first.maxX)
    }

    func testSelectionUsesIdentityAndSurvivesStreamingAppend() throws {
        let surface = BilingualResultContentView()
        let first = TranslationSegment(id: "a", block: "p", kind: .paragraph, source: "Help? ", translation: "帮助？")
        let second = TranslationSegment(id: "b", block: "p", kind: .paragraph, source: "Help?", translation: "再帮？")
        surface.update(source: "Help? Help?", translation: "帮助？再帮？", segments: [first, second], onCopy: { _ in })
        let texts = descendants(surface).compactMap { $0 as? NSTextView }
        XCTAssertEqual(texts.count, 2)
        let source = try XCTUnwrap(texts.first)
        let target = try XCTUnwrap(texts.last)
        source.setSelectedRange(NSRange(location: 6, length: 4))
        XCTAssertNil(background(target, at: 0), "The identical earlier source must not match")
        XCTAssertNotNil(background(target, at: 3))
        surface.update(source: "Help? Help? Next.", translation: "帮助？再帮？下一句。", segments: [first, second,
            TranslationSegment(id: "c", block: "p", kind: .paragraph, source: " Next.", translation: "下一句。")], onCopy: { _ in })
        XCTAssertEqual(source.selectedRange(), NSRange(location: 6, length: 4))
        XCTAssertNotNil(background(target, at: 3))
        XCTAssertNil(background(target, at: 6))
        target.setSelectedRange(NSRange(location: 1, length: 4))
        XCTAssertEqual(source.selectedRange().length, 0)
        XCTAssertNotNil(background(source, at: 0))
        XCTAssertNotNil(background(source, at: 6))
        target.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertNil(background(source, at: 6))
    }

    func testUnicodeSelectionAndColumnCopyRemainIndependent() throws {
        _ = NSApplication.shared
        let surface = BilingualResultContentView()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        surface.update(source: "👩‍💻 Cafe\u{301}. שלום", translation: "开发。你好", segments: [
            TranslationSegment(id: "a", block: "p", kind: .paragraph, source: "👩‍💻 Cafe\u{301}. ", translation: "开发。"),
            TranslationSegment(id: "b", block: "p", kind: .paragraph, source: "שלום", translation: "你好"),
        ], onCopy: { value in
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
        })
        let texts = descendants(surface).compactMap { $0 as? NSTextView }
        let source = try XCTUnwrap(texts.first)
        let target = try XCTUnwrap(texts.last)
        source.setSelectedRange(NSRange(location: 14, length: 2))
        XCTAssertNil(background(target, at: 0))
        XCTAssertNotNil(background(target, at: 3))
        let buttons = descendants(surface).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 2)
        try XCTUnwrap(buttons.first).performClick(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "👩‍💻 Cafe\u{301}. שלום")
        try XCTUnwrap(buttons.last).performClick(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "开发。你好")
        surface.update(source: "Legacy", translation: "", segments: nil, onCopy: { _ in })
        XCTAssertEqual(source.string, "Legacy")
        source.setSelectedRange(NSRange(location: 0, length: 2))
        XCTAssertNil(background(source, at: 0))
        XCTAssertFalse(try XCTUnwrap(buttons.last).isEnabled)
    }

    func testClickingSurfaceWhitespaceClearsLinkedSelection() throws {
        let surface = BilingualResultContentView()
        surface.update(source: "Hello", translation: "你好", segments: [
            TranslationSegment(id: "a", block: "p", kind: .paragraph, source: "Hello", translation: "你好")
        ], onCopy: { _ in })
        let texts = descendants(surface).compactMap { $0 as? NSTextView }
        let source = try XCTUnwrap(texts.first)
        let target = try XCTUnwrap(texts.last)
        source.setSelectedRange(NSRange(location: 0, length: 3))
        XCTAssertNotNil(background(target, at: 0))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        surface.mouseDown(with: event)
        XCTAssertEqual(source.selectedRange().length, 0)
        XCTAssertNil(background(target, at: 0))
    }

    func testHoverAndClickUseGlyphIdentityWithoutOverridingSelection() throws {
        let surface = BilingualResultContentView()
        surface.frame = NSRect(x: 0, y: 0, width: 600, height: 160)
        surface.update(source: "One. Two.", translation: "一。二。", segments: [
            TranslationSegment(id: "a", block: "p", kind: .paragraph, source: "One. ", translation: "一。"),
            TranslationSegment(id: "b", block: "p", kind: .paragraph, source: "Two.", translation: "二。"),
        ], onCopy: { _ in })
        let window = NSWindow(contentRect: surface.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        defer { window.close() }
        surface.layoutSubtreeIfNeeded()
        let source = surface.sourceView
        let target = surface.translationView
        let manager = try XCTUnwrap(source.layoutManager)
        let container = try XCTUnwrap(source.textContainer)
        let glyph = manager.glyphIndexForCharacter(at: 0)
        let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        let point = source.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        }
        source.mouseMoved(with: try event(.mouseMoved))
        let hover = try XCTUnwrap(background(target, at: 0) as? NSColor)
        XCTAssertNil(background(target, at: 2))
        source.mouseUp(with: try event(.leftMouseUp))
        let selected = try XCTUnwrap(background(target, at: 0) as? NSColor)
        XCTAssertNotEqual(hover, selected)
        target.setSelectedRange(NSRange(location: 2, length: 1))
        source.mouseMoved(with: try event(.mouseMoved))
        XCTAssertNil(background(source, at: 0))
        XCTAssertNotNil(background(source, at: 5))
    }

    func testHistoryRendersBilingualLayoutInBothAppearances() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let segments = [
            TranslationSegment(id: "title", block: "h", kind: .heading, source: "Support and feedback", translation: "支持与反馈"),
            TranslationSegment(id: "a", block: "p", kind: .paragraph, source: "Need help? ", translation: "需要帮助？"),
            TranslationSegment(id: "b", block: "p", kind: .paragraph, source: "Contact our support team.", translation: "请联系我们的支持团队。"),
            TranslationSegment(id: "c", block: "p2", kind: .paragraph, source: "Want to give us feedback? ", translation: "想向我们提供反馈？"),
            TranslationSegment(id: "d", block: "p2", kind: .paragraph, source: "Tell us what you think.", translation: "告诉我们您的想法。"),
        ]
        let record = HistoryRecord(operation: StoredOperation(id: UUID(),
            screenshot: ManagedScreenshot(path: "/missing-fixture.png", sha256: "fixture"),
            selection: ProviderSelection(providerID: "deepseek", modelID: "fixture-vision"), status: .succeeded,
            sourceMarkdown: "Support and feedback\n\nNeed help? Contact our support team.\n\nWant to give us feedback? Tell us what you think.",
            translationMarkdown: "支持与反馈\n\n需要帮助？请联系我们的支持团队。\n\n想向我们提供反馈？告诉我们您的想法。",
            kind: .translate, targetLanguage: "zh-Hans", segments: segments), createdAt: Date(timeIntervalSince1970: 1_787_725_812), isPinned: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vlmsnapper-bilingual-renders-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("Bilingual render evidence: \(directory.path)")
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let host = NSHostingView(rootView: ManagementCenterView(destination: .history, records: [record], selectedRecordID: record.id))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            defer { window.close() }
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            let fields = descendants(host).compactMap { $0 as? NSTextView }.filter { $0.isSelectable && !$0.isEditable }
            XCTAssertEqual(fields.count, 2)
            let source = try XCTUnwrap(fields.first)
            let target = try XCTUnwrap(fields.last)
            XCTAssertTrue(source.string.contains("Need help? Contact our support team."))
            XCTAssertTrue(target.string.contains("需要帮助？请联系我们的支持团队。"))
            XCTAssertEqual(source.frame.width, target.frame.width, accuracy: 1)
            source.setSelectedRange((source.string as NSString).range(of: "Need help?"))
            let range = (target.string as NSString).range(of: "需要帮助？")
            XCTAssertNotNil(background(target, at: range.location))
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("history-\(name).png"))
        }
    }

    func testStructuredBlocksAndUntrustedTextStayLiteralAndCopyable() throws {
        _ = NSApplication.shared
        let surface = BilingualResultContentView()
        let source = "Title\n\n- <script>run()</script>\n\n- https://example.invalid/a"
        var copied = ""
        surface.update(source: source, translation: "标题\n\n- 脚本\n\n- 链接", segments: [
            TranslationSegment(id: "h", block: "h", kind: .heading, source: "Title", translation: "标题"),
            TranslationSegment(id: "a", block: "a", kind: .listItem, source: "<script>run()</script>", translation: "脚本"),
            TranslationSegment(id: "b", block: "b", kind: .listItem, source: "https://example.invalid/a", translation: "链接"),
        ], onCopy: { copied = $0 })
        let text = try XCTUnwrap(descendants(surface).compactMap { $0 as? NSTextView }.first)
        XCTAssertEqual(text.string, "Title\n- <script>run()</script>\n- https://example.invalid/a")
        let storage = try XCTUnwrap(text.textStorage)
        XCTAssertEqual((storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 16)
        XCTAssertEqual((storage.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.pointSize, 13)
        var links = 0
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { links += 1 }
        }
        XCTAssertEqual(links, 0)
        XCTAssertFalse(text.isEditable)
        try XCTUnwrap(descendants(surface).compactMap { $0 as? NSButton }.first).performClick(nil)
        XCTAssertEqual(copied, "Title\n\n- <script>run()</script>\n\n- https://example.invalid/a")
    }

    private func background(_ view: NSTextView, at index: Int) -> Any? {
        view.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: index, effectiveRange: nil)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
