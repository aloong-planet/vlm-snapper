import AppKit
import SwiftUI
import Testing
import Vision
import VLMSnapperCore
@testable import VLMSnapperUI

// v1-core::REQ-010. Not covered here, because they depend on the window server and the real event route,
// so only an installed build can show them: whether the box sits above the overlay on screen, and ⌘C
// while the application is not active. Hovering needs a real pointer: the toolbar's selected state under
// the pointer (REQ-013/AC-05) and tooltips appearing are checked on the installed build. The language
// list's check mark is an image with no text to read, also checked there. "Copied" going away after a
// moment needs the main actor free, which a test holding the localization lock cannot give: installed
// build too. SwiftUI exposes no accessibility tree to these windows, so tests read what is rendered with
// text recognition.
@Suite("Capture result box placement")
struct CaptureResultBoxPlacementTests {
    @Test("the box sits at the right and top of the usable area, up to its maximum height")
    func tallScreen() {
        let frame = CaptureResultBoxPlacement.frame(visibleScreenFrame: CGRect(x: 0, y: 72, width: 1_440, height: 800))
        #expect(frame == CGRect(x: 1_048, y: 220, width: 380, height: 640))
    }

    @Test("on a short screen the box fills the usable height less its insets")
    func shortScreen() {
        let frame = CaptureResultBoxPlacement.frame(visibleScreenFrame: CGRect(x: 0, y: 60, width: 1_280, height: 500))
        #expect(frame == CGRect(x: 888, y: 72, width: 380, height: 476))
    }

    @Test("the box follows a display that is not at the origin")
    func offsetScreen() {
        let frame = CaptureResultBoxPlacement.frame(visibleScreenFrame: CGRect(x: -1_920, y: -200, width: 1_920, height: 1_000))
        #expect(frame == CGRect(x: -392, y: 148, width: 380, height: 640))
    }

    @Test("a dragged box stays on the usable area")
    func clampedDrag() {
        let visible = CGRect(x: 0, y: 72, width: 1_440, height: 800)
        let size = CGSize(width: 380, height: 640)
        #expect(CaptureResultBoxPlacement.clampedOrigin(CGPoint(x: -50, y: 0), size: size, visibleScreenFrame: visible) == CGPoint(x: 0, y: 72))
        #expect(CaptureResultBoxPlacement.clampedOrigin(CGPoint(x: 5_000, y: 5_000), size: size, visibleScreenFrame: visible) == CGPoint(x: 1_060, y: 232))
        #expect(CaptureResultBoxPlacement.clampedOrigin(CGPoint(x: 300, y: 100), size: size, visibleScreenFrame: visible) == CGPoint(x: 300, y: 100))
    }
}

@Suite("Capture result box content", .serialized)
@MainActor
struct CaptureResultBoxPresentationTests {
    private func presentation(_ operation: WorkspaceOperationKind, _ slot: WorkspaceOperationSlot) -> CaptureResultBoxPresentation {
        CaptureResultBoxPresentation(
            operation: operation,
            targetLanguageName: "简体中文",
            providerSummary: "DeepSeek · vision",
            slot: slot
        )
    }

    private let segments = [
        TranslationSegment(id: "a", block: "p", kind: .paragraph, source: "Hello", translation: "你好"),
    ]

    @Test("titles name the operation and, for a translation, its language")
    func titles() {
        LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
            #expect(presentation(.extract, WorkspaceOperationSlot()).title == "提取")
            #expect(presentation(.translate, WorkspaceOperationSlot()).title == "翻译 · 简体中文")
            #expect(presentation(.extract, WorkspaceOperationSlot()).providerSummary == "DeepSeek · vision")
        }
    }

    @Test("while preparing, the body says so, progress shows, and nothing can be copied or retried")
    func preparing() {
        LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
            let value = presentation(.extract, WorkspaceOperationSlot(attempt: .preparing))
            #expect(value.body == .message("正在准备请求"))
            #expect(value.showsProgress)
            #expect(!value.canCopy)
            #expect(!value.canRetry)
        }
    }

    @Test("a translation that has only received source text still reads as preparing")
    func translationWithSourceOnly() {
        LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
            let value = presentation(.translate, WorkspaceOperationSlot(attempt: .streaming, sourceDelta: "Hello"))
            #expect(value.body == .message("正在准备请求"))
            #expect(!value.canCopy)
        }
    }

    @Test("streaming shows the operation's own text and can be copied but not retried")
    func streaming() {
        let extract = presentation(.extract, WorkspaceOperationSlot(attempt: .streaming, sourceDelta: "Partial"))
        #expect(extract.body == .text(.extraction(markdown: "Partial")))
        #expect(extract.copyText == "Partial")
        #expect(extract.showsProgress)
        #expect(extract.followsNewText)
        #expect(!extract.canRetry)
        let translate = presentation(.translate, WorkspaceOperationSlot(
            attempt: .streaming, sourceDelta: "Hello", translationDelta: "你好", segments: segments
        ))
        #expect(translate.body == .text(.translation(text: "你好", segments: segments)))
        #expect(translate.copyText == "你好")
    }

    @Test("a finished translation copies only its translation, and an extraction its Markdown")
    func finished() {
        let result = WorkspaceCommittedResult(sourceMarkdown: "# Hello", translationMarkdown: "你好", segments: segments)
        let slot = WorkspaceOperationSlot(attempt: .succeeded, committedResult: result)
        let translate = presentation(.translate, slot)
        #expect(translate.copyText == "你好")
        #expect(!translate.showsProgress)
        #expect(!translate.followsNewText)
        #expect(translate.canRetry)
        #expect(presentation(.extract, slot).copyText == "# Hello")
    }

    @Test("an image without text says so, with nothing to copy and retry available", arguments: [
        WorkspaceOperationKind.extract, .translate,
    ])
    func noText(operation: WorkspaceOperationKind) {
        LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
            let value = presentation(operation, WorkspaceOperationSlot(
                attempt: .succeeded,
                committedResult: WorkspaceCommittedResult(sourceMarkdown: "", translationMarkdown: "")
            ))
            #expect(value.body == .message("图片中没有识别到文字。"))
            #expect(!value.canCopy)
            #expect(value.canRetry)
        }
    }

    @Test("a failure gives its reason and retry, without earlier or partial text")
    func failure() {
        LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
            let value = presentation(.extract, WorkspaceOperationSlot(
                attempt: .failed(code: "first_text_timeout"),
                committedResult: WorkspaceCommittedResult(sourceMarkdown: "Earlier", translationMarkdown: nil),
                sourceDelta: "Partial"
            ))
            #expect(value.body == .failure("等待 Provider 响应超时，请检查网络后手动重试。"))
            #expect(!value.canCopy)
            #expect(value.canRetry)
        }
    }

    @Test("a canceled operation says so and can be retried, without earlier text")
    func canceled() {
        LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
            let value = presentation(.extract, WorkspaceOperationSlot(
                attempt: .canceled,
                committedResult: WorkspaceCommittedResult(sourceMarkdown: "Earlier", translationMarkdown: nil)
            ))
            #expect(value.body == .canceled("已取消"))
            #expect(!value.canCopy)
            #expect(value.canRetry)
        }
    }

    @Test("an unsaved result stays readable and copyable with a notice, and cannot be retried")
    func unsaved() {
        LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
            let value = presentation(.extract, WorkspaceOperationSlot(
                attempt: .resultPersistenceFailed,
                unsavedResult: WorkspaceCommittedResult(sourceMarkdown: "Unsaved", translationMarkdown: nil)
            ))
            #expect(value.body == .text(.extraction(markdown: "Unsaved")))
            #expect(value.copyText == "Unsaved")
            #expect(value.saveNotice == "结果尚未保存，可以先复制并重试保存。")
            #expect(!value.canRetry)
        }
    }

    @Test("the language list's search matches an abbreviation or a name")
    func languageSearch() {
        let tunisian = TargetLanguageOption(code: "aeb", name: "突尼斯阿拉伯语")
        let chinese = TargetLanguageOption(code: "zh-Hans", name: "简体中文")
        #expect(tunisian.abbreviation == "AEB")
        #expect(chinese.abbreviation == "ZH")
        #expect(tunisian.matches("aeb"))
        #expect(tunisian.matches("阿拉伯"))
        #expect(!tunisian.matches("中文"))
        #expect(chinese.matches("zh"))
        #expect(chinese.matches("  "))
    }
}

@Suite("Capture result box in a window", .serialized)
@MainActor
struct CaptureResultBoxWindowTests {
    private static let provider = "DeepSeek · a-model-name-long-enough-to-be-cut-short-in-the-header"

    private func slot(streaming text: String) -> WorkspaceOperationSlot {
        WorkspaceOperationSlot(attempt: .streaming, sourceDelta: text)
    }

    private func finished(_ text: String) -> WorkspaceOperationSlot {
        WorkspaceOperationSlot(
            attempt: .succeeded,
            committedResult: WorkspaceCommittedResult(sourceMarkdown: text, translationMarkdown: nil)
        )
    }

    private func presentation(
        _ slot: WorkspaceOperationSlot,
        operation: WorkspaceOperationKind = .extract,
        retryAvailable: Bool = true
    ) -> CaptureResultBoxPresentation {
        CaptureResultBoxPresentation(
            operation: operation,
            targetLanguageName: "简体中文",
            providerSummary: Self.provider,
            slot: slot,
            retryAvailable: retryAvailable
        )
    }

    private func makeController(
        copied: CopyLog = CopyLog()
    ) throws -> (CaptureResultBoxPanelController, NSWindow) {
        let controller = CaptureResultBoxPanelController(
            actions: CaptureResultBoxActions(
                onCopy: { copied.values.append($0) },
                onRetry: { copied.retries += 1 },
                onRetrySave: {},
                onClose: { copied.closes += 1 }
            ),
            onEscape: { copied.escapes += 1 }
        )
        controller.state.presentation = presentation(finished("Text"))
        let screen = try #require(NSScreen.main)
        controller.show(on: screen)
        let panel = try #require(NSApp.windows.first { $0.isVisible && $0.contentView is NSHostingView<CaptureResultBoxView> })
        pump(panel)
        return (controller, panel)
    }

    private func pump(_ window: NSWindow) {
        for _ in 0..<5 {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            window.layoutIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func textView(_ window: NSWindow) throws -> ResultBoxTextView {
        let content = try #require(window.contentView)
        return try #require(descendants(content).compactMap { $0 as? ResultBoxTextView }.first)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func send(_ type: NSEvent.EventType, at point: NSPoint, to window: NSWindow) throws {
        window.sendEvent(try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1
        )))
    }

    private func key(_ characters: String, code: UInt16, command: Bool = false, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: command ? [.command] : [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        ))
    }

    private func longText(_ paragraphs: Int) -> String {
        (1...paragraphs).map { "Paragraph \($0) with enough words to fill a line of the result box." }.joined(separator: "\n\n")
    }

    @Test("the box takes the keyboard but keeps the application's level and does not close itself")
    func panelBehavior() throws {
        let log = CopyLog()
        let (controller, panel) = try makeController(copied: log)
        defer { controller.reset() }
        #expect(panel.canBecomeKey)
        #expect(panel.level.rawValue == NSWindow.Level.screenSaver.rawValue + 1)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.hidesOnDeactivate)

        panel.cancelOperation(nil)

        #expect(log.escapes == 1)
        #expect(panel.isVisible)
    }

    @Test("dragging the header moves the box and keeps it on the display; a press on a button does not")
    func headerDrag() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        let screen = try #require(panel.screen)
        let start = panel.frame.origin
        let header = NSPoint(x: panel.frame.width / 2, y: panel.frame.height - CaptureResultBoxMetrics.headerHeight / 2)

        try send(.leftMouseDown, at: header, to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: header.x - 100, y: header.y - 30), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: header.x - 100, y: header.y - 30), to: panel)
        pump(panel)
        #expect(panel.frame.origin == CGPoint(x: start.x - 100, y: start.y - 30))

        let moved = panel.frame.origin
        let title = NSPoint(x: 20, y: header.y)
        try send(.leftMouseDown, at: title, to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: title.x - 5_000, y: title.y), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: title.x - 5_000, y: title.y), to: panel)
        pump(panel)
        #expect(panel.frame.minX == screen.visibleFrame.minX, "dragging on the title works and stops at the edge")
        #expect(panel.frame.origin.y == moved.y)

        let placed = panel.frame.origin
        let closeButton = NSPoint(x: panel.frame.width - 18, y: header.y)
        try send(.leftMouseDown, at: closeButton, to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: closeButton.x - 80, y: closeButton.y), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: closeButton.x - 80, y: closeButton.y), to: panel)
        pump(panel)
        #expect(panel.frame.origin == placed)
    }

    @Test("a dragged box comes back where it was during the capture, and the next capture starts over")
    func draggedPositionLastsForTheCapture() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        let screen = try #require(panel.screen)
        let original = panel.frame
        let header = NSPoint(x: panel.frame.width / 2, y: panel.frame.height - CaptureResultBoxMetrics.headerHeight / 2)
        try send(.leftMouseDown, at: header, to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: header.x - 120, y: header.y), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: header.x - 120, y: header.y), to: panel)
        pump(panel)
        let moved = panel.frame

        controller.hide()
        #expect(controller.frame == nil)
        controller.show(on: screen)
        #expect(panel.frame == moved)

        controller.reset()
        controller.state.presentation = presentation(finished("Text"))
        controller.show(on: screen)
        #expect(panel.frame == original)
    }

    @Test("Escape from the text view leaves the capture, and ⌘C and ⌘A act on its text")
    func keyboard() throws {
        let log = CopyLog()
        let (controller, panel) = try makeController(copied: log)
        defer { controller.reset() }
        panel.makeKey()
        let text = try textView(panel)
        panel.makeFirstResponder(text)

        text.keyDown(with: try key("\u{1b}", code: 53, window: panel))
        #expect(log.escapes == 1)

        #expect(panel.performKeyEquivalent(with: try key("a", code: 0, command: true, window: panel)))
        #expect(text.selectedRange() == NSRange(location: 0, length: text.string.utf16.count))
        #expect(panel.performKeyEquivalent(with: try key("c", code: 8, command: true, window: panel)))
        #expect(log.values == ["Text"])

        text.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(panel.performKeyEquivalent(with: try key("c", code: 8, command: true, window: panel)))
        #expect(log.values == ["Text"], "nothing selected copies nothing")
    }

    @Test("the right-click menu holds only Copy and Select All")
    func contextMenu() throws {
        try LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
            let (controller, panel) = try makeController()
            defer { controller.reset() }
            let text = try textView(panel)
            let event = try #require(NSEvent.mouseEvent(
                with: .rightMouseDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            ))

            let menu = try #require(text.menu(for: event))

            #expect(menu.items.map(\.title) == ["复制", "全选"])
            #expect(menu.allowsContextMenuPlugIns == false, "Services would open apps behind the overlay")
        }
    }

    @Test("a translation box shows only the translation")
    func translationOnly() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        controller.state.presentation = presentation(WorkspaceOperationSlot(
            attempt: .succeeded,
            committedResult: WorkspaceCommittedResult(
                sourceMarkdown: "Need help?",
                translationMarkdown: "需要帮助？",
                segments: [TranslationSegment(id: "a", block: "p", kind: .paragraph, source: "Need help?", translation: "需要帮助？")]
            )
        ), operation: .translate)
        pump(panel)

        #expect(try textView(panel).string == "需要帮助？")
    }

    // Shaped after stored extractions: blank-line blocks, code fences, inline code and HTML-like tags.
    @Test("an extraction is one selectable text, with markup and code kept as plain characters")
    func extractionShape() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        let markdown = """
        # Title

        Use `value` and <div class="x">tags</div> [a link](https://example.com).

        ```swift
        let a = 1

        let b = 2
        ```

        - First item
        - Second item

        | A | B |
        """
        controller.state.presentation = presentation(finished(markdown))
        pump(panel)

        let content = try #require(panel.contentView)
        let views = descendants(content).compactMap { $0 as? NSTextView }
        #expect(views.count == 1)
        let text = try textView(panel)
        #expect(text.string == """
        Title
        Use `value` and <div class="x">tags</div> [a link](https://example.com).
        ```swift
        let a = 1

        let b = 2
        ```
        - First item
        - Second item
        | A | B |
        """)
        #expect(text.isEditable == false)
        #expect(text.isAutomaticLinkDetectionEnabled == false)
        let storage = try #require(text.textStorage)
        var links = 0
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { links += 1 }
        }
        #expect(links == 0)
        let heading = try #require(text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(heading.pointSize == 16)
        text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
        #expect(text.selectedRange().length == text.string.utf16.count)
    }

    @Test("a line that starts right-to-left reads from the right, with its left-to-right words after it")
    func rightToLeftExtraction() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        let mixed = "مرحبا hello"
        controller.state.presentation = presentation(finished(mixed))
        pump(panel)
        let text = try textView(panel)
        let manager = try #require(text.layoutManager)
        manager.ensureLayout(for: try #require(text.textContainer))

        #expect(text.string == mixed)
        let firstWord = manager.location(forGlyphAt: manager.glyphIndexForCharacter(at: 0)).x
        let secondWord = manager.location(forGlyphAt: manager.glyphIndexForCharacter(at: 6)).x
        #expect(firstWord > secondWord, "first word at \(firstWord), second at \(secondWord)")
    }

    // Shaped after stored translations (counted 2026-11-03: 55 blocks, 14 with several segments, 8 of those
    // list items): a heading, then a paragraph and a list item of two sentences each, then another list item.
    private let blocks = [
        TranslationSegment(id: "h", block: "b1", kind: .heading, source: "Title", translation: "标题"),
        TranslationSegment(id: "p1", block: "b2", kind: .paragraph, source: "One.", translation: "正文第一句。"),
        TranslationSegment(id: "p2", block: "b2", kind: .paragraph, source: "Two.", translation: "正文第二句。"),
        TranslationSegment(id: "a1", block: "b3", kind: .listItem, source: "Three.", translation: "第一项第一句。"),
        TranslationSegment(id: "a2", block: "b3", kind: .listItem, source: "Four.", translation: "第一项第二句。"),
        TranslationSegment(id: "b", block: "b4", kind: .listItem, source: "Five", translation: "第二项"),
    ]

    private func translating(_ segments: [TranslationSegment]) -> WorkspaceOperationSlot {
        WorkspaceOperationSlot(
            attempt: .streaming,
            translationDelta: TranslationSegment.text(segments, translated: true),
            segments: segments
        )
    }

    private func translated(_ segments: [TranslationSegment]) -> WorkspaceOperationSlot {
        WorkspaceOperationSlot(attempt: .succeeded, committedResult: WorkspaceCommittedResult(
            sourceMarkdown: TranslationSegment.text(segments, translated: false),
            translationMarkdown: TranslationSegment.text(segments, translated: true),
            segments: segments
        ))
    }

    @Test("a translation's blocks grow in one selectable text, and a selection lasts through the end of the stream")
    func translationBlocksKeepSelection() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        controller.state.presentation = presentation(translating(Array(blocks.prefix(1))), operation: .translate)
        pump(panel)
        let text = try textView(panel)
        text.setSelectedRange(NSRange(location: 0, length: 2))

        controller.state.presentation = presentation(translating(Array(blocks.prefix(2))), operation: .translate)
        pump(panel)
        #expect(text.selectedRange() == NSRange(location: 0, length: 2))
        // A second sentence joins its block with no separator or second list marker.
        controller.state.presentation = presentation(translating(Array(blocks.prefix(3))), operation: .translate)
        pump(panel)
        #expect(text.string == "标题\n正文第一句。正文第二句。")
        #expect(text.selectedRange() == NSRange(location: 0, length: 2))
        controller.state.presentation = presentation(translating(blocks), operation: .translate)
        pump(panel)
        #expect(text.string == "标题\n正文第一句。正文第二句。\n- 第一项第一句。第一项第二句。\n- 第二项")
        #expect(text.selectedRange() == NSRange(location: 0, length: 2))
        let content = try #require(panel.contentView)
        #expect(descendants(content).compactMap { $0 as? NSTextView }.count == 1)
        let heading = try #require(text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(heading.pointSize == 16)

        controller.state.presentation = presentation(translated(blocks), operation: .translate)
        pump(panel)
        #expect(text.string == "标题\n正文第一句。正文第二句。\n- 第一项第一句。第一项第二句。\n- 第二项")
        #expect(text.selectedRange() == NSRange(location: 0, length: 2))
    }

    @Test("a translation follows its end until the reader scrolls up, and the end of the stream leaves them there")
    func translationFollowsUnlessScrolledUp() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        func paragraphs(_ count: Int) -> [TranslationSegment] {
            (1...count).map {
                TranslationSegment(id: "s\($0)", block: "b\($0)", kind: .paragraph, source: "Source \($0)",
                                   translation: "第 \($0) 段译文，长度足够占满结果框里的一整行文字才能撑开滚动区域。")
            }
        }
        controller.state.presentation = presentation(translating(paragraphs(60)), operation: .translate)
        pump(panel)
        let content = try #require(panel.contentView)
        let scroll = try #require(descendants(content).compactMap { $0 as? ResultBoxScrollView }.first)
        let text = try textView(panel)
        #expect(text.bounds.height > text.visibleRect.height, "the text must overflow")
        #expect(text.visibleRect.maxY >= text.bounds.height - 4)

        controller.state.presentation = presentation(translating(paragraphs(70)), operation: .translate)
        pump(panel)
        #expect(text.visibleRect.maxY >= text.bounds.height - 4)

        text.scroll(NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        controller.state.presentation = presentation(translating(paragraphs(80)), operation: .translate)
        pump(panel)
        #expect(text.visibleRect.minY == 100)
        controller.state.presentation = presentation(translated(paragraphs(80)), operation: .translate)
        pump(panel)
        #expect(text.visibleRect.minY == 100)
    }

    @Test("the end of an extraction's stream keeps a selection and the reading place")
    func extractionEndKeepsSelection() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        controller.state.presentation = presentation(slot(streaming: longText(60)))
        pump(panel)
        let content = try #require(panel.contentView)
        let scroll = try #require(descendants(content).compactMap { $0 as? ResultBoxScrollView }.first)
        let text = try textView(panel)
        text.setSelectedRange(NSRange(location: 3, length: 9))
        text.scroll(NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)

        // The last chunk and the end of the stream arrive together.
        controller.state.presentation = presentation(finished(longText(61)))
        pump(panel)

        #expect(text.string.contains("Paragraph 61"))
        #expect(text.selectedRange() == NSRange(location: 3, length: 9))
        #expect(text.visibleRect.minY == 100)
    }

    @Test("a reader at the end when the last chunk and the end of the stream arrive together stays at the end")
    func readerAtTheEndStaysThereWhenTheStreamEnds() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        controller.state.presentation = presentation(slot(streaming: longText(60)))
        pump(panel)
        let text = try textView(panel)
        #expect(text.bounds.height > text.visibleRect.height, "the text must overflow")
        #expect(text.visibleRect.maxY >= text.bounds.height - 4)

        controller.state.presentation = presentation(finished(longText(70)))
        pump(panel)

        #expect(text.string.contains("Paragraph 70"))
        #expect(text.visibleRect.maxY >= text.bounds.height - 4)
    }

    @Test("the header shows the Provider and model, with the full text in its tooltip")
    func headerShowsProvider() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        let content = try #require(panel.contentView)

        #expect(try recognizedText(in: content).contains("DeepSeek"))
        #expect(descendants(content).compactMap { $0 as? ResultBoxDragView }.first?.toolTip == Self.provider)
    }

    @Test("the preparing, failure and canceled bodies show their words, and the body's Retry acts")
    func bodiesShowTheirWords() throws {
        try LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .english)
            let log = CopyLog()
            let (controller, panel) = try makeController(copied: log)
            defer { controller.reset() }
            let content = try #require(panel.contentView)

            controller.state.presentation = presentation(WorkspaceOperationSlot(attempt: .preparing))
            pump(panel)
            #expect(try recognizedText(in: content).contains("Preparing request"))

            controller.state.presentation = presentation(WorkspaceOperationSlot(attempt: .failed(code: "first_text_timeout")))
            pump(panel)
            #expect(try recognizedText(in: content).contains("The Provider response timed out"))
            try pressBodyRetry(panel)
            #expect(log.retries == 1)

            controller.state.presentation = presentation(WorkspaceOperationSlot(attempt: .canceled))
            pump(panel)
            #expect(try recognizedText(in: content).contains("Canceled"))
            try pressBodyRetry(panel)
            #expect(log.retries == 2)
        }
    }

    @Test("while another result is unsaved, neither Retry acts", arguments: [
        WorkspaceAttemptState.failed(code: "first_text_timeout"), .canceled,
    ])
    func retryWaitsForAnUnsavedResult(attempt: WorkspaceAttemptState) throws {
        try LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .english)
            let log = CopyLog()
            let (controller, panel) = try makeController(copied: log)
            defer { controller.reset() }
            controller.state.presentation = presentation(WorkspaceOperationSlot(attempt: attempt), retryAvailable: false)
            pump(panel)
            #expect(controller.state.presentation?.canRetry == false)

            try pressBodyRetry(panel)
            let header = NSPoint(
                x: panel.frame.width - 6 - 12.5 - VLMSnapperUIConstants.toolbarControlHeight - VLMSnapperUIConstants.toolbarControlGap,
                y: panel.frame.height - CaptureResultBoxMetrics.headerHeight / 2
            )
            try send(.leftMouseDown, at: header, to: panel)
            try send(.leftMouseUp, at: header, to: panel)
            pump(panel)

            #expect(log.retries == 0)
        }
    }

    @Test("the body's Retry looks unavailable while another result is unsaved, and available otherwise")
    func bodyRetryLooksUnavailable() throws {
        try LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .english)
            let (controller, panel) = try makeController()
            defer { controller.reset() }
            let content = try #require(panel.contentView)
            let failed = WorkspaceOperationSlot(attempt: .failed(code: "first_text_timeout"))

            controller.state.presentation = presentation(failed)
            pump(panel)
            let label = try #require(try recognizedLines(in: content).first { $0.text == "Retry" })
            let available = try inkContrast(in: content, box: label.box)

            controller.state.presentation = presentation(failed, retryAvailable: false)
            pump(panel)
            let unavailable = try inkContrast(in: content, box: label.box)

            #expect(available - unavailable > 0.2, "available \(available), unavailable \(unavailable)")
        }
    }

    @Test("the header's Retry and Copy look unavailable when they are")
    func headerIconsLookUnavailable() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        let content = try #require(panel.contentView)
        func icon(fromEnd index: CGFloat) -> CGRect {
            let step = VLMSnapperUIConstants.toolbarControlHeight + VLMSnapperUIConstants.toolbarControlGap
            let inWindow = NSPoint(
                x: panel.frame.width - 6 - VLMSnapperUIConstants.toolbarControlHeight / 2 - index * step,
                y: panel.frame.height - CaptureResultBoxMetrics.headerHeight / 2
            )
            let center = content.convert(inWindow, from: nil)
            return CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
        }

        controller.state.presentation = presentation(finished("Text"))
        pump(panel)
        let retryAvailable = try inkContrast(in: content, box: icon(fromEnd: 1))
        let copyAvailable = try inkContrast(in: content, box: icon(fromEnd: 2))

        controller.state.presentation = presentation(finished("Text"), retryAvailable: false)
        pump(panel)
        let retryUnavailable = try inkContrast(in: content, box: icon(fromEnd: 1))
        #expect(retryAvailable - retryUnavailable > 0.2, "available \(retryAvailable), unavailable \(retryUnavailable)")

        controller.state.presentation = presentation(WorkspaceOperationSlot(attempt: .failed(code: "first_text_timeout")))
        pump(panel)
        let copyUnavailable = try inkContrast(in: content, box: icon(fromEnd: 2))
        #expect(copyAvailable - copyUnavailable > 0.2, "available \(copyAvailable), unavailable \(copyUnavailable)")
    }

    /// The header's Retry is an icon, so the word can only be the body's button.
    private func pressBodyRetry(_ panel: NSWindow) throws {
        let content = try #require(panel.contentView)
        let label = try #require(try recognizedLines(in: content).first { $0.text == "Retry" })
        let point = content.convert(NSPoint(x: label.box.midX, y: label.box.midY), to: nil)
        try send(.leftMouseDown, at: point, to: panel)
        try send(.leftMouseUp, at: point, to: panel)
        pump(panel)
    }

    @Test("the Copy button says it copied")
    func copySaysCopied() throws {
        try LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .english)
            let (controller, panel) = try makeController()
            defer { controller.reset() }
            let content = try #require(panel.contentView)
            #expect(try !recognizedText(in: content).contains("Copied"))
            let copy = NSPoint(
                x: panel.frame.width - 6 - 12.5 - 2 * (VLMSnapperUIConstants.toolbarControlHeight + VLMSnapperUIConstants.toolbarControlGap),
                y: panel.frame.height - CaptureResultBoxMetrics.headerHeight / 2
            )

            try send(.leftMouseDown, at: copy, to: panel)
            try send(.leftMouseUp, at: copy, to: panel)
            pump(panel)
            #expect(try recognizedText(in: content).contains("Copied"))
        }
    }

    @Test("a long URL wraps inside the box instead of widening it")
    func longURLWraps() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        controller.state.presentation = presentation(finished("https://example.com/" + String(repeating: "a-very-long-path-", count: 30)))
        pump(panel)
        let text = try textView(panel)
        let manager = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        manager.ensureLayout(for: container)

        #expect(manager.usedRect(for: container).width <= container.size.width + 1)
        #expect(manager.usedRect(for: container).height > 40, "it takes several lines")
        #expect(text.frame.width <= panel.frame.width)
    }

    @Test("appended text keeps a selection")
    func appendKeepsSelection() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        controller.state.presentation = presentation(slot(streaming: "First paragraph."))
        pump(panel)
        let text = try textView(panel)
        text.setSelectedRange(NSRange(location: 0, length: 5))

        controller.state.presentation = presentation(slot(streaming: "First paragraph.\n\nSecond paragraph."))
        pump(panel)

        #expect(text.string.contains("Second paragraph."))
        #expect(text.selectedRange() == NSRange(location: 0, length: 5))
    }

    @Test("streaming follows the end until the reader scrolls up, and again once back at the end")
    func followsUnlessScrolledUp() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        controller.state.presentation = presentation(slot(streaming: longText(60)))
        pump(panel)
        let content = try #require(panel.contentView)
        let scroll = try #require(descendants(content).compactMap { $0 as? ResultBoxScrollView }.first)
        let text = try textView(panel)
        func isAtEnd() -> Bool { text.visibleRect.maxY >= text.bounds.height - 4 }
        #expect(text.frame.height > scroll.contentView.bounds.height, "the text must overflow")
        #expect(isAtEnd())

        controller.state.presentation = presentation(slot(streaming: longText(70)))
        pump(panel)
        #expect(isAtEnd())

        text.scroll(NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        controller.state.presentation = presentation(slot(streaming: longText(80)))
        pump(panel)
        #expect(text.visibleRect.minY == 100, "the reader stays where they scrolled")

        text.scrollToEndOfDocument(nil)
        scroll.reflectScrolledClipView(scroll.contentView)
        pump(panel)
        controller.state.presentation = presentation(slot(streaming: longText(90)))
        pump(panel)
        #expect(isAtEnd())
    }

    @Test("a finished result shown for the first time opens at its top")
    func finishedOpensAtTop() throws {
        let (controller, panel) = try makeController()
        defer { controller.reset() }
        controller.state.presentation = nil
        pump(panel)
        controller.state.presentation = presentation(finished(longText(60)))
        pump(panel)
        let text = try textView(panel)

        #expect(text.bounds.height > text.visibleRect.height, "the text must overflow")
        #expect(text.visibleRect.minY == 0)
    }

    @Test("the header's buttons act, with Retry unavailable while running")
    func headerButtons() throws {
        let log = CopyLog()
        let (controller, panel) = try makeController(copied: log)
        defer { controller.reset() }
        let y = panel.frame.height - CaptureResultBoxMetrics.headerHeight / 2
        func button(fromEnd index: CGFloat) -> NSPoint {
            NSPoint(x: panel.frame.width - 6 - 12.5 - index * (VLMSnapperUIConstants.toolbarControlHeight + VLMSnapperUIConstants.toolbarControlGap), y: y)
        }
        func press(_ point: NSPoint) throws {
            try send(.leftMouseDown, at: point, to: panel)
            try send(.leftMouseUp, at: point, to: panel)
            pump(panel)
        }

        try press(button(fromEnd: 0))
        #expect(log.closes == 1)
        try press(button(fromEnd: 1))
        #expect(log.retries == 1)
        try press(button(fromEnd: 2))
        #expect(log.values == ["Text"])

        controller.state.presentation = presentation(slot(streaming: "Partial"))
        pump(panel)
        try press(button(fromEnd: 1))
        #expect(log.retries == 1)
    }

    @Test("a long Provider and model leave room for the buttons")
    func longProviderDoesNotPushButtons() throws {
        let log = CopyLog()
        let (controller, panel) = try makeController(copied: log)
        defer { controller.reset() }
        let close = NSPoint(
            x: panel.frame.width - 6 - 12.5,
            y: panel.frame.height - CaptureResultBoxMetrics.headerHeight / 2
        )
        try send(.leftMouseDown, at: close, to: panel)
        try send(.leftMouseUp, at: close, to: panel)
        pump(panel)
        #expect(log.closes == 1)
    }
}

/// How far the darkest and lightest pixels of a rendered area are apart, for a label's strength.
@MainActor
func inkContrast(in view: NSView, box: CGRect) throws -> CGFloat {
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    let minRow = view.isFlipped ? box.minY : view.bounds.height - box.maxY
    var levels: [CGFloat] = []
    for row in Int(minRow * scale)..<Int((minRow + box.height) * scale) {
        for column in Int(box.minX * scale)..<Int(box.maxX * scale) {
            guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
            levels.append((color.redComponent + color.greenComponent + color.blueComponent) / 3)
        }
    }
    return try #require(levels.max()) - (try #require(levels.min()))
}

/// The lines of text a view renders, with where each one is in the view's coordinates.
@MainActor
func recognizedLines(in view: NSView) throws -> [(text: String, box: CGRect)] {
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["en-US", "zh-Hans"]
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage), options: [:]).perform([request])
    return (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        let box = observation.boundingBox
        let height = box.height * view.bounds.height
        let minY = (view.isFlipped ? 1 - box.maxY : box.minY) * view.bounds.height
        return (text, CGRect(x: box.minX * view.bounds.width, y: minY, width: box.width * view.bounds.width, height: height))
    }
}

@MainActor
func recognizedText(in view: NSView) throws -> String {
    try recognizedLines(in: view).map(\.text).joined(separator: "\n")
}

@MainActor
private final class CopyLog {
    var values: [String] = []
    var retries = 0
    var closes = 0
    var escapes = 0
}
