import AppKit
import Foundation
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// Snap regions (v1-core::REQ-006): hover latency with many windows and the real window list of
// a signed sandboxed app are checked on the installed build, not here.
extension ProviderApplicationTests {
    // v1-core::REQ-006: a click selects the snap region from the window list taken with the
    // freeze. The selection shows through the toolbar, which is left-aligned with it.
    @Test
    func clickOnWindowSelectsWholeWindow() async throws {
        try await withSnapFixture { fixture, screen, model in
            try fixture.shortcuts.fire()
            let overlay = try await frozenMainOverlay()
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 301, y: 251), to: overlay)
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            #expect(abs(toolbar.frame.minX - (screen.frame.minX + 200)) <= 1)
            #expect(toolbar.frame.maxY <= screen.frame.minY + 150)
        }
    }

    @Test
    func clickOnDesktopSelectsWholeDisplay() async throws {
        try await withSnapFixture { fixture, screen, model in
            try fixture.shortcuts.fire()
            let overlay = try await frozenMainOverlay()
            try sendMouse(.leftMouseDown, at: NSPoint(x: 60, y: 600), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 60, y: 600), to: overlay)
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            // No room below or above a whole display: inside its bottom-right corner, 4 pt in.
            #expect(abs(toolbar.frame.maxX - (screen.visibleFrame.maxX - 4)) <= 1)
        }
    }

    @Test
    func clickWhileFreezingSelectsWindowOnceFramesArrive() async throws {
        try await withSnapFixture { fixture, screen, model in
            await fixture.capture.holdFrames()
            try fixture.shortcuts.fire()
            try await eventually { try mainScreenOverlay() != nil }
            let overlay = try #require(try mainScreenOverlay())
            pumpNativeEvents(overlay)
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
            #expect(captureToolbar() == nil)
            await fixture.capture.release()
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            #expect(abs(toolbar.frame.minX - (screen.frame.minX + 200)) <= 1)
        }
    }

    @Test
    func clickWithoutWindowListSelectsNothingButDragStillWorks() async throws {
        try await withSnapFixture(windowList: false) { fixture, screen, model in
            try fixture.shortcuts.fire()
            let overlay = try await frozenMainOverlay()
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
            // Selections are handled in order: the toolbar that appears belongs to the drag.
            try drag(overlay, from: NSPoint(x: 120, y: 200), to: NSPoint(x: 260, y: 320))
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            #expect(abs(toolbar.frame.minX - (screen.frame.minX + 120)) <= 1)
        }
    }

    @Test
    func lateWindowListOfReplacedCaptureIsIgnored() async throws {
        try await withSnapFixture(windowList: false) { fixture, screen, model in
            let flipHeight = try #require(NSScreen.screens.first).frame.height
            func list(atLocalX x: CGFloat) -> CaptureWindowSnapshot {
                CaptureWindowSnapshot(windows: [CaptureWindowSnapshotEntry(
                    ownerProcessID: 4242, layer: 0, alpha: 1, isOnScreen: true,
                    bounds: CGRect(x: screen.frame.minX + x, y: flipHeight - (screen.frame.minY + 350), width: 300, height: 200)
                )], dockProcessID: nil)
            }
            // The first capture's list has a window at local x 200, the replacement's at x 700.
            await fixture.windows.provide(perCall: [list(atLocalX: 200), list(atLocalX: 700)])
            await fixture.windows.hold()
            let first = try await completeSelection(fixture).overlay
            await fixture.capture.holdFrames()
            try fixture.shortcuts.fire()
            try await eventually { try mainScreenOverlay().map { $0 !== first } ?? false }
            let overlay = try #require(try mainScreenOverlay())
            pumpNativeEvents(overlay)
            // The replacement's list arrives first, the first capture's afterwards. Click only
            // after both have been handed over, or the first list would resolve the click.
            await fixture.windows.release(newestFirst: true)
            try await eventually { await fixture.windows.returned == 2 }
            try await Task.sleep(for: .milliseconds(100))
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
            await fixture.capture.release()
            try await eventually { try overlayShowsFrozenFrame(overlay) && captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            // Local x 300 has no window in the replacement's list: the whole display is selected, so the
            // toolbar sits inside its bottom-right corner.
            #expect(abs(toolbar.frame.maxX - (screen.visibleFrame.maxX - 4)) <= 1)
        }
    }

    @Test
    func windowListIsReadOnceAtTriggerWithoutOwnWindows() async throws {
        try await withSnapFixture(windowList: false) { fixture, screen, model in
            let flipHeight = try #require(NSScreen.screens.first).frame.height
            func entry(_ process: Int32, localX x: CGFloat, width: CGFloat) -> CaptureWindowSnapshotEntry {
                CaptureWindowSnapshotEntry(
                    ownerProcessID: process, layer: 0, alpha: 1, isOnScreen: true,
                    bounds: CGRect(x: screen.frame.minX + x, y: flipHeight - (screen.frame.minY + 350), width: width, height: 200)
                )
            }
            // First read: one of VLMSnapper's own windows in front at local x 280, a window at 200.
            // A second read before the click would move the toolbar to the display's edge; one after
            // it leaves the toolbar alone and is caught by the call count.
            let own = ProcessInfo.processInfo.processIdentifier
            await fixture.windows.provide(perCall: [
                CaptureWindowSnapshot(windows: [entry(own, localX: 280, width: 100), entry(4242, localX: 200, width: 300)], dockProcessID: nil),
                CaptureWindowSnapshot(windows: [], dockProcessID: nil),
            ])
            await fixture.capture.holdFrames()
            try fixture.shortcuts.fire()
            try await eventually { await fixture.windows.calls == 1 }
            try await eventually { try mainScreenOverlay() != nil }
            let overlay = try #require(try mainScreenOverlay())
            pumpNativeEvents(overlay)
            try await Task.sleep(for: .milliseconds(100))
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
            await fixture.capture.release()
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            #expect(abs(toolbar.frame.minX - (screen.frame.minX + 200)) <= 1)
            // Give any read started at commit time to reach the adapter before counting.
            try await Task.sleep(for: .milliseconds(100))
            #expect(await fixture.windows.calls == 1)
        }
    }

    @Test
    func heldWindowListDoesNotDelayOverlay() async throws {
        try await withSnapFixture { fixture, _, model in
            await fixture.windows.hold()
            try fixture.shortcuts.fire()
            try await eventually { try mainScreenOverlay() != nil }
            let overlay = try #require(try mainScreenOverlay())
            try await eventually { try overlayShowsFrozenFrame(overlay) }
            await fixture.windows.release()
        }
    }
}
