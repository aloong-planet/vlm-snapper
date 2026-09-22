import AppKit
import SwiftUI
import Testing
@testable import VLMSnapperUI

@Suite("Menu bar panel action buttons", .serialized)
@MainActor
struct MenuBarPanelActionButtonTests {
    @Test("the complete visible row is clickable")
    func completeRowIsClickable() throws {
        var actionCount = 0
        let hostingView = NSHostingView(
            rootView: MenuBarPanelActionButton(role: .row) {
                actionCount += 1
            } label: {
                Text("Action")
            }
            .frame(width: 240, height: 44)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 44)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        try click(window: window, at: NSPoint(x: 235, y: 22))
        try #require(waitForNativeCondition(timeout: 0.01) { actionCount == 1 })
        #expect(actionCount == 1)
    }

    @Test("every action role has a visible hover response")
    func everyRoleHasHoverResponse() {
        for role in MenuBarPanelActionRole.allCases {
            #expect(role.backgroundOpacity(isHovering: false) != role.backgroundOpacity(isHovering: true))
        }
    }

    private func click(window: NSWindow, at point: NSPoint) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 1,
                    clickCount: 1,
                    pressure: 1
                )
            )
            window.sendEvent(event)
        }
    }
}
