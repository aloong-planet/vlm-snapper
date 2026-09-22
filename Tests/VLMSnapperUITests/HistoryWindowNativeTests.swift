import AppKit
import SwiftUI
import XCTest
import VLMSnapperCore
import VLMSnapperUI

// Run in an isolated test process: activation belongs to the native application.
// This exercises production window construction and mouse delivery, not a
// direct assignment to the list selection or its callback.
@MainActor
final class HistoryWindowNativeTests: XCTestCase {
    func testMenuFooterRoutesExistingManagementWindow() async throws {
        let application = NSApplication.shared
        let oldDelegate = application.delegate
        let oldPolicy = application.activationPolicy()
        application.delegate = nil
        _ = application.setActivationPolicy(.accessory)
        defer { application.delegate = oldDelegate; _ = application.setActivationPolicy(oldPolicy) }
        let management = ManagementCenterWindowController(records: [record("History")])
        let window = try XCTUnwrap(management.window)
        defer { window.close() }
        management.show(destination: .history)
        try await settle(window, condition: "history initially shown") {
            window.contentView.map { !historyRenderedRows(in: $0).isEmpty } == true
        }
        var route: ManagementCenterDestination?
        let menu = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 210),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        menu.isReleasedWhenClosed = false
        defer { menu.close() }
        menu.contentView = NSHostingView(rootView: MenuBarPanelView(
            recentItems: [], onCapture: {}, onOpenRecent: { _ in },
            onNavigate: { route = $0; management.show(destination: $0) }, onCheckUpdates: {}))
        for (x, destination) in [(75.0, ManagementCenterDestination.providerSettings), (225.0, .settings)] {
            route = nil
            menu.makeKeyAndOrderFront(nil)
            try await settle(menu, condition: "menu key window") { menu.isKeyWindow }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                menu.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 20),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: menu.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)))
            }
            try await settle(window, condition: "footer routes to requested page") { route == destination }
            try await settle(window, condition: "history no longer displayed") {
                window.contentView.map { historyRenderedRows(in: $0).isEmpty } == true
            }
        }
        management.show(destination: .history)
        try await settle(window, condition: "explicit return to history") {
            window.contentView.map { !historyRenderedRows(in: $0).isEmpty } == true
        }
    }

    func testOpeningFillsAvailableScreenAndPreservesUserResize() throws {
        let controller = ManagementCenterWindowController(records: [record("History record")])
        guard let window = controller.window else { return XCTFail("Missing management window") }
        defer { window.close() }
        controller.show(destination: .history)
        window.layoutIfNeeded()
        let visibleFrame = try XCTUnwrap(window.screen).visibleFrame
        XCTAssertEqual(window.frame, visibleFrame)
        XCTAssertFalse(window.styleMask.contains(.fullScreen))
        // An oversized fixture is constrained by AppKit when the window is shown again.
        let availableContentSize = window.contentRect(forFrameRect: visibleFrame).size
        let resizedContentSize = NSSize(
            width: min(1100, availableContentSize.width - 40),
            height: min(700, availableContentSize.height)
        )
        guard resizedContentSize.width >= window.contentMinSize.width,
              resizedContentSize.height >= window.contentMinSize.height else {
            return XCTFail("The test display must support a smaller window above the content minimum")
        }
        window.setContentSize(resizedContentSize)
        let resizedFrame = window.frame
        XCTAssertEqual(window.contentRect(forFrameRect: resizedFrame).size, resizedContentSize)
        XCTAssertTrue(visibleFrame.contains(resizedFrame))
        XCTAssertNotEqual(resizedFrame, visibleFrame)
        controller.hideForCapture()
        controller.show(destination: .settings)
        window.layoutIfNeeded()
        XCTAssertEqual(window.frame, resizedFrame)
    }

    func testSingleClickSelectsAnotherHistoryRecord() async throws {
        let application = NSApplication.shared
        let oldDelegate = application.delegate
        let oldPolicy = application.activationPolicy()
        application.delegate = nil
        defer {
            application.delegate = oldDelegate
            _ = application.setActivationPolicy(oldPolicy)
        }
        XCTAssertTrue(application.setActivationPolicy(.accessory))
        let first = record("First history record")
        let second = record("Second history record")
        var selected: UUID?
        var opened: UUID?
        let controller = ManagementCenterWindowController(
            records: [first, second], selectedRecordID: first.id,
            callbacks: ManagementCenterCallbacks(
                onSelectRecord: { selected = $0 }, onOpenRecord: { opened = $0 }
            )
        )
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.show(destination: .history)
        try await settle(window, condition: "key window") { window.isKeyWindow }
        let content = try XCTUnwrap(window.contentView)
        let list = historyRenderedRows(in: content)
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(try XCTUnwrap(list.first).isSelected())
        let row = window.convertFromScreen(list[1].screenFrame())
        for type in [NSEvent.EventType.leftMouseUp, .leftMouseDown] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: row.midX, y: row.midY),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            ))
            if type == .leftMouseUp {
                application.postEvent(event, atStart: true)
            } else {
                window.sendEvent(event)
                // NSTableView consumes mouse-up inside its tracking loop;
                // a SwiftUI recognizer returns immediately and needs normal
                // application dispatch of the still-queued mouse-up instead.
                if let up = application.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                    window.sendEvent(up)
                }
            }
        }
        try await settle(window, condition: "second record selected") { selected == second.id }
        XCTAssertTrue(try XCTUnwrap(historyRenderedRows(in: content).dropFirst().first).isSelected())
        XCTAssertEqual(selected, second.id)
        XCTAssertNil(opened, "Single click must not open the result workspace")
        let firstRow = window.convertFromScreen(try XCTUnwrap(historyRenderedRows(in: content).first).screenFrame())
        for count in [1, 2] {
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp,
                location: NSPoint(x: firstRow.midX, y: firstRow.midY), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: count + 2, clickCount: count, pressure: 0))
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                location: up.locationInWindow, modifierFlags: [], timestamp: up.timestamp,
                windowNumber: window.windowNumber, context: nil, eventNumber: count + 2,
                clickCount: count, pressure: 1))
            application.postEvent(up, atStart: true)
            window.sendEvent(down)
            if let pending = application.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                window.sendEvent(pending)
            }
        }
        try await settle(window, condition: "double click selects first record inline") { selected == first.id }
        XCTAssertEqual(selected, first.id)
        XCTAssertNil(opened, "Double click must not open a separate result workspace")
    }

    private func settle(_ window: NSWindow, condition: String, until predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        repeat {
            if let event = NSApp.nextEvent(matching: .appKitDefined, until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            window.layoutIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        } while Date() < deadline
        throw NSError(domain: "HistoryWindowNativeTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Native history condition timed out: \(condition)"
        ])
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func record(_ text: String) -> HistoryRecord {
        HistoryRecord(operation: StoredOperation(
            id: UUID(), screenshot: ManagedScreenshot(path: "/missing-fixture.png", sha256: "fixture"),
            selection: ProviderSelection(providerID: "deepseek", modelID: "fixture-model"),
            status: .succeeded, sourceMarkdown: text, kind: .extract
        ), createdAt: Date(timeIntervalSince1970: 1_787_725_812), isPinned: false)
    }
}
