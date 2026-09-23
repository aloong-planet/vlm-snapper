import AppKit
import SwiftUI
import XCTest
import VLMSnapperCore
@testable import VLMSnapperUI

// Use the XCTest host for these event-driven tests. On the investigated runtime,
// the Swift Testing host exited from its async main drain before completing this
// suite; the XCTest host completed the same interactions and assertions.
// Keep the window lifecycle before the combined interaction in this regression.
// Synthetic events and rendering do not prove physical input or VoiceOver.
// External AX covers preview open/resize/close. Escape, parent-window close,
// and long-image scrolling still require installed-app interaction acceptance.
@MainActor
final class HistoryInteractionTests: XCTestCase {
    func test01InitialDetailLoadsForRetry() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let fixtures = records
        var selected: UUID?
        let hosting = NSHostingView(rootView: ManagementCenterView(
            destination: .history, records: fixtures, selectedRecordID: fixtures[0].id,
            callbacks: ManagementCenterCallbacks(onSelectRecord: { selected = $0 })
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        window.orderFront(nil)
        try settle(window) { selected == fixtures[0].id }
        XCTAssertTrue(selected == fixtures[0].id)
    }

    func test02HistoricalProviderFiltersList() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let controller = ManagementCenterWindowController(records: records)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.show(destination: .history)
        let content = try XCTUnwrap(window.contentView)
        try settle(window) { historyRenderedRows(in: content).count == 2 }
        let picker = try XCTUnwrap(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        XCTAssertTrue(picker.itemTitles == ["All Providers", "DeepSeek", "OpenAI"])
        try XCTUnwrap(picker.menu).performActionForItem(at: picker.indexOfItem(withTitle: "OpenAI"))
        try settle(window) { historyRenderedRows(in: content).count == 1 }
        let labels = accessibleText(content)
        XCTAssertTrue(labels.contains("OpenAI translation"))
        XCTAssertTrue(!labels.contains("DeepSeek extraction"))
    }

    func test03QueryWindowLifetime() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let controller = ManagementCenterWindowController(records: records)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.show(destination: .history)
        var content = try XCTUnwrap(window.contentView)
        try settle(window) { historyRenderedRows(in: content).count == 2 }
        let picker = try XCTUnwrap(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        try XCTUnwrap(picker.menu).performActionForItem(at: picker.indexOfItem(withTitle: "OpenAI"))
        try settle(window) { historyRenderedRows(in: content).count == 1 }
        controller.hideForCapture()
        controller.show(destination: .history)
        try settle(window) { historyRenderedRows(in: content).count == 1 }
        window.performClose(nil)
        controller.show(destination: .history)
        content = try XCTUnwrap(window.contentView)
        try settle(window) { historyRenderedRows(in: content).count == 2 }
        let reopened = try XCTUnwrap(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        XCTAssertTrue(reopened.titleOfSelectedItem == "All Providers")
    }


    func test04CombinedQueryAndSelection() async throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let previousDelegate = application.delegate
        application.delegate = nil
        defer {
            application.delegate = previousDelegate
            _ = application.setActivationPolicy(previousPolicy)
        }
        try XCTUnwrap((application.setActivationPolicy(.accessory)) ? true : nil)
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let fixtures = [
            record("deepseek", source: "First source", kind: .extract),
            record("deepseek", source: "Translation source", kind: .translate),
            record("deepseek", source: "Second source", kind: .extract, pinned: false),
            record("openai", source: "Other source", kind: .extract),
        ]
        var opened: UUID?
        let controller = ManagementCenterWindowController(
            records: fixtures, callbacks: ManagementCenterCallbacks(onOpenRecord: { opened = $0 })
        )
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.show(destination: .history)
        pump(window)
        try await settle(in: window) { window.isKeyWindow }
        try XCTUnwrap((window.isKeyWindow) ? true : nil, "Native mouse acceptance requires a real key window")
        let content = try XCTUnwrap(window.contentView)
        // Native mouse events hit the production controls at the approved toolbar geometry.
        try click(window, at: NSPoint(x: 330, y: content.bounds.height - 29))
        try settle(window) { historyRenderedRows(in: content).count == 3 }
        let picker = try XCTUnwrap(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        try XCTUnwrap(picker.menu).performActionForItem(at: picker.indexOfItem(withTitle: "DeepSeek"))
        var list: [HistoryRenderedRow] = []
        try settle(window) {
            list = historyRenderedRows(in: content)
            return list.count == 2
        }
        let row = window.convertFromScreen(list[1].screenFrame())
        try click(window, at: NSPoint(x: row.midX, y: row.midY))
        try await settle(in: window) { historyRenderedRows(in: content).dropFirst().first?.isSelected() == true }
        XCTAssertTrue(opened == nil)
        try enterSearch("source", in: window)
        try settle(window) {
            let rows = historyRenderedRows(in: content)
            return rows.count == 2 && rows[1].isSelected()
        }
        try click(window, at: NSPoint(x: 90, y: content.bounds.height - 213))
        try settle(window) { historyRenderedRows(in: content).isEmpty }
        try click(window, at: NSPoint(x: 90, y: content.bounds.height - 61))
        try await settle(in: window) {
            let rows = historyRenderedRows(in: content)
            return rows.count == 2 && rows[1].isSelected()
        }
        try click(window, at: NSPoint(x: 90, y: content.bounds.height - 101))
        try settle(window) { historyRenderedRows(in: content).count == 1 && accessibleText(content).contains("First source") }
        XCTAssertTrue(accessibleText(content).contains("First source"))
        try click(window, at: NSPoint(x: 90, y: content.bounds.height - 61))
        try settle(window) { historyRenderedRows(in: content).count == 2 }
        try enterSearch("unmatched", in: window)
        try settle(window) { historyRenderedRows(in: content).isEmpty && !accessibleText(content).contains("First source") && !accessibleText(content).contains("Second source") }
        XCTAssertTrue(!accessibleText(content).contains("First source"))
        XCTAssertTrue(!accessibleText(content).contains("Second source"))
        try click(window, at: NSPoint(x: 225, y: content.bounds.height - 29))
        try enterSearch("needle", in: window)
        try settle(window) { historyRenderedRows(in: content).count == 1 && accessibleText(content).contains("Translation source") }
        XCTAssertTrue(accessibleText(content).contains("Translation source"))
    }

    func test05HistoryRenders() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("vlmsnapper-history-ui-sync")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixtures = [
            record("deepseek", source: "Designing Calm Software", kind: .translate),
            record("openai", source: "Vision API integration guide", kind: .extract, status: .canceled),
            record("gemini", source: "Provider request failed", kind: .translate, status: .failed),
            record("deepseek", source: "Interrupted operation", kind: .extract, status: .interrupted),
        ]
        for language in [EffectiveApplicationLanguage.simplifiedChinese, .english] {
            VLMSnapperLocalization.configure(effectiveLanguage: language)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for width in [920, 1200] {
                    let hosting = NSHostingView(rootView: ManagementCenterView(
                        destination: .history, records: fixtures, selectedRecordID: fixtures[0].id
                    ))
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: width == 1200 ? 780 : 620),
                                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = hosting
                    window.appearance = NSAppearance(named: appearance)
                    window.orderFront(nil)
                    try settle(window) {
                        let rows = historyRenderedRows(in: hosting)
                        return rows.count == 4 && abs(historySelectedWidth(in: rows[0]) - 249) < 1
                    }
                    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: output.appendingPathComponent("\(language)-\(appearance.rawValue)-\(width).png"))
                    window.close()
                }
            }
        }
    }

    func test06HistoryThumbnailKeepsAspectRatioAndHeight() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let fixtures = records
        let image = NSImage(size: NSSize(width: 1200, height: 300))
        image.lockFocus()
        NSColor(srgbRed: 0.2, green: 0.8, blue: 0.6, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 300).fill()
        image.unlockFocus()
        let hosting = NSHostingView(rootView: ManagementCenterView(
            destination: .history, records: fixtures, selectedRecordID: fixtures[0].id, selectedImage: image
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        window.orderFront(nil)
        pump(window)
        // SwiftUI virtual controls are not exported in-process here. External
        // AX scenarios exercise opening/closing; this test measures real pixels.
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to:
            FileManager.default.temporaryDirectory.appendingPathComponent("vlmsnapper-history-detail-layout.png"))
        let pixels = try XCTUnwrap(NSBitmapImageRep(data: png)?.converting(to: .sRGB, renderingIntent: .default))
        let scale = CGFloat(pixels.pixelsWide) / hosting.bounds.width
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<pixels.pixelsHigh {
            for x in Int(450 * scale)..<pixels.pixelsWide {
                guard let color = pixels.colorAt(x: x, y: y),
                    abs(color.redComponent - 0.2) < 0.02,
                    abs(color.greenComponent - 0.8) < 0.02,
                    abs(color.blueComponent - 0.6) < 0.02 else { continue }
                xs.append(x); ys.append(y)
            }
        }
        let width = CGFloat(try XCTUnwrap(xs.max()) - XCTUnwrap(xs.min()) + 1) / scale
        let height = CGFloat(try XCTUnwrap(ys.max()) - XCTUnwrap(ys.min()) + 1) / scale
        XCTAssertEqual(height, 100, accuracy: 2)
        XCTAssertEqual(width, 400, accuracy: 2)
    }

    func test07ArrowKeysSelectHistoryAndRespectSearchFocus() async throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let previousDelegate = application.delegate
        application.delegate = nil
        defer {
            application.delegate = previousDelegate
            _ = application.setActivationPolicy(previousPolicy)
        }
        XCTAssertTrue(application.setActivationPolicy(.accessory))
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let fixtures = [
            record("deepseek", source: "First source", kind: .extract),
            record("deepseek", source: "Second source", kind: .extract, pinned: false),
            record("openai", source: "Third source", kind: .extract),
        ]
        var selected: UUID?
        var opened: UUID?
        var retried: UUID?
        let controller = ManagementCenterWindowController(records: fixtures, callbacks: ManagementCenterCallbacks(
            onSelectRecord: { selected = $0 }, onOpenRecord: { opened = $0 }, onRetryRecord: { retried = $0 }
        ))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.show(destination: .history)
        try await settle(in: window) { window.isKeyWindow }
        let content = try XCTUnwrap(window.contentView)
        try await settle(in: window) { historyRenderedRows(in: content).count == 3 }
        let row = window.convertFromScreen(historyRenderedRows(in: content)[0].screenFrame())
        try click(window, at: NSPoint(x: row.midX, y: row.midY))
        XCTAssertEqual(selected, fixtures[0].id)
        try pressArrow(.downArrow, in: window)
        try await settle(in: window) { selected == fixtures[1].id }
        XCTAssertTrue(historyRenderedRows(in: content)[1].isSelected())
        controller.update(records: fixtures, selectedRecordID: fixtures[1].id, selectedImage: nil,
                          cleanupFailureCount: 0, retention: .thirtyDays,
                          settings: GeneralSettingsSnapshot(), providerSettings: nil)
        pump(window)
        try pressArrow(.downArrow, in: window, modifiers: .shift)
        XCTAssertEqual(selected, fixtures[1].id, "Modified arrows must not navigate records")
        try pressArrow(.downArrow, in: window)
        try await settle(in: window) { selected == fixtures[2].id }
        try pressArrow(.downArrow, in: window)
        XCTAssertEqual(selected, fixtures[2].id)
        try pressArrow(.upArrow, in: window)
        try await settle(in: window) { selected == fixtures[1].id }
        try pressArrow(.upArrow, in: window)
        try await settle(in: window) { selected == fixtures[0].id }
        try pressArrow(.upArrow, in: window)
        XCTAssertEqual(selected, fixtures[0].id)
        try enterSearch("source", in: window)
        try pressArrow(.downArrow, in: window)
        XCTAssertEqual(selected, fixtures[0].id, "Search owns arrow keys while editing")
        XCTAssertNil(opened, "Navigation must not open a result window")
        XCTAssertNil(retried, "Navigation must not send a provider request")

        // Pinned is an intersection of the same visible list, not all history.
        try click(window, at: NSPoint(x: 90, y: content.bounds.height - 101))
        try await settle(in: window) { historyRenderedRows(in: content).count == 2 }
        let pinnedRow = window.convertFromScreen(historyRenderedRows(in: content)[0].screenFrame())
        try click(window, at: NSPoint(x: pinnedRow.midX, y: pinnedRow.midY))
        try pressArrow(.downArrow, in: window)
        try await settle(in: window) { selected == fixtures[2].id }
        XCTAssertTrue(historyRenderedRows(in: content)[1].isSelected())
        try pressArrow(.downArrow, in: window)
        XCTAssertEqual(selected, fixtures[2].id)

        let picker = try XCTUnwrap(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        try XCTUnwrap(picker.menu).performActionForItem(at: picker.indexOfItem(withTitle: "DeepSeek"))
        try await settle(in: window) { historyRenderedRows(in: content).count == 1 && selected == fixtures[0].id }
        let onlyRow = window.convertFromScreen(historyRenderedRows(in: content)[0].screenFrame())
        try click(window, at: NSPoint(x: onlyRow.midX, y: onlyRow.midY))
        try pressArrow(.downArrow, in: window)
        try pressArrow(.upArrow, in: window)
        XCTAssertEqual(selected, fixtures[0].id)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            pump(window)
            let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: FileManager.default.temporaryDirectory
                .appendingPathComponent("history-arrow-focus-\(appearance.rawValue).png"))
        }
        try enterSearch("no matching record", in: window)
        try await settle(in: window) { historyRenderedRows(in: content).isEmpty }
        try pressArrow(.downArrow, in: window)
        XCTAssertTrue(historyRenderedRows(in: content).isEmpty)
    }

    func test08ArrowSelectionScrollsAndKeyboardCanEnterList() async throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let previousDelegate = application.delegate
        application.delegate = nil
        defer {
            application.delegate = previousDelegate
            _ = application.setActivationPolicy(previousPolicy)
        }
        XCTAssertTrue(application.setActivationPolicy(.accessory))
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let fixtures = (1...18).map { record("deepseek", source: "History entry \($0)", kind: .extract) }
        var selected: UUID?
        let controller = ManagementCenterWindowController(records: fixtures,
            callbacks: ManagementCenterCallbacks(onSelectRecord: { selected = $0 }))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.show(destination: .history)
        window.setContentSize(NSSize(width: 920, height: 620))
        try await settle(in: window) { window.isKeyWindow }
        let content = try XCTUnwrap(window.contentView)
        try await settle(in: window) { !historyRenderedRows(in: content).isEmpty }
        try enterSearch("History entry", in: window)
        // Tab follows the actual key-view loop from search into the record pane.
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48
            )))
        }
        pump(window)
        try pressArrow(.downArrow, in: window)
        try await settle(in: window) { selected == fixtures[1].id }
        let scroll = try XCTUnwrap(historyRenderedRows(in: content).first?.scroll)
        let initialOffset = scroll.contentView.bounds.origin.y
        for record in fixtures.dropFirst(2) {
            try pressArrow(.downArrow, in: window)
            try await settle(in: window) { selected == record.id }
        }
        try await settle(in: window) {
            scroll.contentView.bounds.origin.y > initialOffset && historyRenderedRows(in: content).contains { $0.isSelected() }
        }
        XCTAssertEqual(selected, fixtures[17].id)
        XCTAssertTrue(accessibleText(content).contains("History entry 18"))
    }

    private func pressArrow(_ key: KeyEquivalent, in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws {
        let down = key == .downArrow
        let characters = String(UnicodeScalar(down ? NSDownArrowFunctionKey : NSUpArrowFunctionKey)!)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers.union([.function, .numericPad]),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: down ? 125 : 126
            )))
        }
        pump(window)
    }

    private func enterSearch(_ text: String, in window: NSWindow) throws {
        let content = try XCTUnwrap(window.contentView)
        let field = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTextField }
            .first { $0.isEditable && !($0 is NSSecureTextField) })
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        pump(window)
    }

    private func click(_ window: NSWindow, at point: NSPoint) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
            )))
        }
        pump(window)
    }

    private var records: [HistoryRecord] {
        [record("deepseek", source: "DeepSeek extraction", kind: .extract),
         record("openai", source: "OpenAI translation", kind: .translate)]
    }

    private func record(_ provider: String, source: String, kind: PersistedOperationKind,
                        pinned: Bool = true, status: OperationStatus = .succeeded) -> HistoryRecord {
        HistoryRecord(
            operation: StoredOperation(
                id: UUID(), screenshot: ManagedScreenshot(path: "/missing-fixture.png", sha256: "fixture"),
                selection: ProviderSelection(providerID: provider, modelID: "fixture-model"),
                status: status, sourceMarkdown: source,
                translationMarkdown: kind == .translate ? "Translated needle" : nil, kind: kind
            ), createdAt: Date(timeIntervalSince1970: 1_787_725_812), isPinned: pinned
        )
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func accessibleText(_ element: any NSAccessibilityProtocol) -> String {
        let own = [element.accessibilityLabel(), element.accessibilityValue() as? String]
            .compactMap { $0 }.joined(separator: " ")
        let children = (element.accessibilityChildren() ?? []) + ((element as? NSView)?.subviews ?? [])
        return own + " " + children.compactMap {
            $0 as? any NSAccessibilityProtocol
        }.map(accessibleText).joined(separator: " ")
    }

    private func pump(_ window: NSWindow) {
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func settle(_ window: NSWindow, file: StaticString = #filePath, line: UInt = #line,
                        until predicate: () -> Bool) throws {
        _ = try XCTUnwrap(waitForNativeCondition(timeout: 0.1) {
            pump(window)
            return predicate()
        } ? true : nil, "History UI condition did not settle within 100 ms", file: file, line: line)
    }

    private struct NativeConditionTimeout: Error {}

    private func settle(in window: NSWindow, file: StaticString = #filePath, line: UInt = #line,
                        until predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while true {
            if let event = NSApp.nextEvent(matching: .appKitDefined, until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            pump(window)
            if predicate() { return }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                XCTFail("Native condition did not settle", file: file, line: line)
                throw NativeConditionTimeout()
            }
            try await Task.sleep(for: .seconds(min(0.01, remaining)))
        }
    }
}
