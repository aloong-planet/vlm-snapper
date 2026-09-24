import AppKit
import SwiftUI
import XCTest
@testable import VLMSnapperUI

// Exercises AppKit event dispatch and a real SwiftUI sheet, not physical device delivery.
// Installed-app acceptance must also click outside the preview with a real pointer.
@MainActor
final class HistoryPreviewDismissalTests: XCTestCase {
    func testBackdropClickDismissesOnlyPreview() throws {
        try withSheet { parent, state in
            let sheet = try XCTUnwrap(parent.attachedSheet)
            let point = NSPoint(x: 20, y: 20)
            XCTAssertFalse(sheet.frame.contains(parent.convertPoint(toScreen: point)))
            try click(parent, point: point)
            XCTAssertTrue(wait { parent.attachedSheet == nil })
            XCTAssertFalse(state.presented)
            XCTAssertTrue(parent.isVisible)
            XCTAssertEqual(state.backgroundClicks, 0)
        }
    }

    func testInteriorAndOtherWindowClicksDoNotDismiss() throws {
        try withSheet { parent, state in
            let sheet = try XCTUnwrap(parent.attachedSheet)
            let content = try XCTUnwrap(sheet.contentView)
            try click(sheet, point: content.convert(NSPoint(x: content.bounds.midX, y: content.bounds.midY), to: nil))
            XCTAssertTrue(state.presented)
            XCTAssertTrue(parent.attachedSheet === sheet)
            let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false
            other.orderFront(nil)
            defer { other.close() }
            try click(other, point: NSPoint(x: 20, y: 20))
            XCTAssertTrue(state.presented)
            XCTAssertTrue(parent.attachedSheet === sheet)
        }
    }

    func testDragFromPreviewToBackdropDoesNotDismiss() throws {
        try withSheet { parent, state in
            let sheet = try XCTUnwrap(parent.attachedSheet)
            let content = try XCTUnwrap(sheet.contentView)
            let point = content.convert(NSPoint(x: content.bounds.midX, y: content.bounds.midY), to: nil)
            try send(.leftMouseDown, window: sheet, point: point)
            try send(.leftMouseUp, window: parent, point: NSPoint(x: 20, y: 20))
            XCTAssertTrue(state.presented)
            XCTAssertTrue(parent.attachedSheet === sheet)
        }
    }

    func testBackdropPressMustEndAsClickRatherThanDrag() throws {
        try withSheet { parent, state in
            try send(.leftMouseDown, window: parent, point: NSPoint(x: 20, y: 20))
            XCTAssertTrue(state.presented)
            try send(.leftMouseUp, window: parent, point: NSPoint(x: 60, y: 60))
            XCTAssertTrue(state.presented)
            XCTAssertEqual(state.backgroundClicks, 0)
            try click(parent, point: NSPoint(x: 20, y: 20))
            XCTAssertTrue(wait { parent.attachedSheet == nil && !state.presented })
        }
    }

    func testDismissReopenAndRemoveMonitor() throws {
        try withSheet { parent, state in
            for _ in 0..<2 {
                try click(parent, point: NSPoint(x: 20, y: 20))
                XCTAssertTrue(wait { parent.attachedSheet == nil && !state.presented })
                state.presented = true
                XCTAssertTrue(wait { parent.attachedSheet?.isVisible == true })
            }
            try click(parent, point: NSPoint(x: 20, y: 20))
            XCTAssertTrue(wait { parent.attachedSheet == nil && !state.presented })
            try click(parent, point: NSPoint(x: 20, y: 20))
            XCTAssertTrue(wait { state.backgroundClicks == 1 })
        }
    }

    private func withSheet(_ body: (NSWindow, PreviewState) throws -> Void) throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        let state = PreviewState()
        let parent = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1200, height: 850),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.contentView = NSHostingView(rootView: PreviewHost(state: state))
        parent.orderFront(nil)
        defer {
            if let sheet = parent.attachedSheet { parent.endSheet(sheet) }
            parent.close()
        }
        state.presented = true
        XCTAssertTrue(wait { parent.attachedSheet?.isVisible == true })
        try body(parent, state)
    }

    private func click(_ window: NSWindow, point: NSPoint) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            try send(type, window: window, point: point)
        }
    }

    private func send(_ type: NSEvent.EventType, window: NSWindow, point: NSPoint) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        NSApp.sendEvent(event)
    }

    private func wait(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }
}

@MainActor
private final class PreviewState: ObservableObject {
    @Published var presented = false
    var backgroundClicks = 0
}

private struct PreviewHost: View {
    @ObservedObject var state: PreviewState
    var body: some View {
        BackgroundClickTarget(onClick: { state.backgroundClicks += 1 })
            .sheet(isPresented: $state.presented) {
                HistoryImagePreview(image: NSImage(size: NSSize(width: 800, height: 200)))
            }
    }
}

private struct BackgroundClickTarget: NSViewRepresentable {
    let onClick: () -> Void
    func makeNSView(context: Context) -> ClickTargetView { ClickTargetView() }
    func updateNSView(_ view: ClickTargetView, context: Context) { view.onClick = onClick }
}

private final class ClickTargetView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }
}
