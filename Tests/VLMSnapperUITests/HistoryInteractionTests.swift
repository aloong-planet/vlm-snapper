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
        pump(window)
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
        pump(window)
        let content = try XCTUnwrap(window.contentView)
        XCTAssertTrue(historyRenderedRows(in: content).count == 2)
        let picker = try XCTUnwrap(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        XCTAssertTrue(picker.itemTitles == ["All Providers", "DeepSeek", "OpenAI"])
        try XCTUnwrap(picker.menu).performActionForItem(at: picker.indexOfItem(withTitle: "OpenAI"))
        pump(window)
        XCTAssertTrue(historyRenderedRows(in: content).count == 1)
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
        pump(window)
        var content = try XCTUnwrap(window.contentView)
        let picker = try XCTUnwrap(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        try XCTUnwrap(picker.menu).performActionForItem(at: picker.indexOfItem(withTitle: "OpenAI"))
        pump(window)
        XCTAssertTrue(historyRenderedRows(in: content).count == 1)
        controller.hideForCapture()
        controller.show(destination: .history)
        pump(window)
        XCTAssertTrue(historyRenderedRows(in: content).count == 1)
        window.performClose(nil)
        controller.show(destination: .history)
        pump(window)
        content = try XCTUnwrap(window.contentView)
        let reopened = try XCTUnwrap(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        XCTAssertTrue(reopened.titleOfSelectedItem == "All Providers")
        XCTAssertTrue(historyRenderedRows(in: content).count == 2)
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
        XCTAssertTrue(historyRenderedRows(in: content).count == 3)
        let picker = try XCTUnwrap(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        try XCTUnwrap(picker.menu).performActionForItem(at: picker.indexOfItem(withTitle: "DeepSeek"))
        pump(window)
        let list = historyRenderedRows(in: content)
        XCTAssertTrue(list.count == 2)
        try XCTUnwrap((list.count == 2) ? true : nil)
        let row = window.convertFromScreen(list[1].screenFrame())
        try click(window, at: NSPoint(x: row.midX, y: row.midY))
        try await settle(in: window) { historyRenderedRows(in: content).dropFirst().first?.isSelected() == true }
        XCTAssertTrue(historyRenderedRows(in: content).dropFirst().first?.isSelected() == true)
        XCTAssertTrue(opened == nil)
        try enterSearch("source", in: window)
        XCTAssertTrue(historyRenderedRows(in: content).dropFirst().first?.isSelected() == true)
        try click(window, at: NSPoint(x: 90, y: content.bounds.height - 213))
        try click(window, at: NSPoint(x: 90, y: content.bounds.height - 61))
        try await settle(in: window) { !historyRenderedRows(in: content).isEmpty }
        XCTAssertTrue(historyRenderedRows(in: content).count == 2)
        XCTAssertTrue(historyRenderedRows(in: content).dropFirst().first?.isSelected() == true)
        try click(window, at: NSPoint(x: 90, y: content.bounds.height - 101))
        XCTAssertTrue(historyRenderedRows(in: content).count == 1)
        XCTAssertTrue(accessibleText(content).contains("First source"))
        try click(window, at: NSPoint(x: 90, y: content.bounds.height - 61))
        XCTAssertTrue(historyRenderedRows(in: content).count == 2)
        try enterSearch("unmatched", in: window)
        XCTAssertTrue(!accessibleText(content).contains("First source"))
        XCTAssertTrue(!accessibleText(content).contains("Second source"))
        try click(window, at: NSPoint(x: 225, y: content.bounds.height - 29))
        try enterSearch("needle", in: window)
        XCTAssertTrue(historyRenderedRows(in: content).count == 1)
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
                    pump(window)
                    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: output.appendingPathComponent("\(language)-\(appearance.rawValue)-\(width).png"))
                    let rows = historyRenderedRows(in: hosting)
                    try XCTUnwrap((rows.count == 4) ? true : nil)
                    XCTAssertTrue(abs(historySelectedWidth(in: rows[0]) - 249) < 1)
                    window.close()
                }
            }
        }
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
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func settle(in window: NSWindow, until predicate: () -> Bool) async throws {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !predicate() && Date() < deadline {
            if let event = NSApp.nextEvent(matching: .appKitDefined, until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            pump(window)
            try await Task.sleep(for: .milliseconds(10))
        }
        try XCTUnwrap((predicate()) ? true : nil, "Native condition did not settle")
    }
}
