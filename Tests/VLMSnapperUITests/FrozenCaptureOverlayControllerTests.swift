import AppKit
import CoreGraphics
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Frozen capture overlay", .serialized)
@MainActor
struct FrozenCaptureOverlayControllerTests {
    @Test("a replacement that cannot cover a display keeps the current overlay")
    func failedReplacementKeepsCurrentOverlay() throws {
        let screen = try #require(NSScreen.screens.first)
        let displayID = try #require(
            (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value
        )
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }

        #expect(present(controller))
        #expect(controller.commit(displays: [makeDisplay(id: displayID, screen: screen)]))
        let currentDisplayIDs = controller.presentedDisplayIDs
        let current = visibleOverlays()
        #expect(!current.isEmpty)

        #expect(present(controller))
        let pending = visibleOverlays()
        #expect(!pending.isEmpty)
        #expect(current.allSatisfy { !$0.isVisible })
        let failedReplacement = controller.commit(displays: [])
        #expect(!failedReplacement)
        controller.rollback()

        #expect(controller.presentedDisplayIDs == currentDisplayIDs)
        #expect(current.allSatisfy { $0.isVisible && $0.contentView != nil })
        #expect(pending.allSatisfy { !$0.isVisible })
    }

    // The open animation scales only the composited window: frame and window-server
    // bounds already equal the screen, so the window's behavior is the observable here.
    @Test("the pending overlay covers each display without an opening animation")
    func pendingOverlayAppearsWithoutOpeningAnimation() {
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }

        #expect(present(controller))

        let overlays = visibleOverlays()
        #expect(!overlays.isEmpty)
        #expect(overlays.allSatisfy { $0.animationBehavior == .none })
    }

    // Snap regions (v1-core::REQ-006). The resolver gets two windows in global top-left
    // coordinates on the primary display; expected frames are those windows flipped by hand
    // against the display height. Not covered here, checked on the installed build: hover from
    // physical mouse movement, real window lists and hover latency with many windows; and with two
    // displays: panels away from the origin, the pointer opening on another display and the region
    // clearing when the pointer leaves a display (this suite runs on the primary display only).
    @Test("a click selects the whole snap region under the pointer")
    func clickSelectsSnapRegion() throws {
        let screen = try primaryScreen()
        let height = screen.frame.height
        var selections: [CGRect] = []
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { selections.append($0.screenFrame) }, onCancel: {})
        #expect(presented)
        let committed = controller.commit(displays: [makeDisplay(id: try displayID(screen), screen: screen)])
        #expect(committed)
        controller.attachSnapRegions(twoWindowResolver())
        let panel = try primaryOverlay()

        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 252, y: height - 199))

        #expect(selections == [CGRect(x: 100, y: height - 300, width: 300, height: 200)])
    }

    @Test("a press moved past three points draws a manual rectangle instead")
    func dragIgnoresSnapRegion() throws {
        let screen = try primaryScreen()
        let height = screen.frame.height
        var selections: [CGRect] = []
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { selections.append($0.screenFrame) }, onCancel: {})
        #expect(presented)
        let committed = controller.commit(displays: [makeDisplay(id: try displayID(screen), screen: screen)])
        #expect(committed)
        controller.attachSnapRegions(twoWindowResolver())
        let panel = try primaryOverlay()

        try send(.leftMouseDown, at: NSPoint(x: 250, y: height - 200), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 290, y: height - 170), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: 290, y: height - 160), to: panel)

        #expect(selections == [CGRect(x: 250, y: height - 200, width: 40, height: 40)])
    }

    @Test("a click before the window list and the frame completes once both arrive")
    func clickBeforeSnapRegionsCompletesLater() throws {
        let screen = try primaryScreen()
        let height = screen.frame.height
        var selections: [CGRect] = []
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { selections.append($0.screenFrame) }, onCancel: {})
        #expect(presented)
        let panel = try primaryOverlay()

        try click(panel, from: NSPoint(x: 750, y: height - 200), to: NSPoint(x: 750, y: height - 200))
        #expect(selections.isEmpty)
        controller.attachSnapRegions(twoWindowResolver())
        #expect(selections.isEmpty)
        let committed = controller.commit(displays: [makeDisplay(id: try displayID(screen), screen: screen)])
        #expect(committed)

        #expect(selections == [CGRect(x: 600, y: height - 300, width: 300, height: 200)])
    }

    @Test("without a window list a click selects nothing")
    func clickWithoutSnapRegionsSelectsNothing() throws {
        let screen = try primaryScreen()
        let height = screen.frame.height
        var selections: [CGRect] = []
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { selections.append($0.screenFrame) }, onCancel: {})
        #expect(presented)
        let committed = controller.commit(displays: [makeDisplay(id: try displayID(screen), screen: screen)])
        #expect(committed)
        controller.attachSnapRegions(nil)
        let panel = try primaryOverlay()

        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))

        #expect(selections.allSatisfy { $0.isEmpty })
    }

    @Test("the overlay opens on the snap region under the pointer and follows it")
    func hoverShowsAndFollowsSnapRegion() throws {
        let screen = try primaryScreen()
        let height = screen.frame.height
        let controller = FrozenCaptureOverlayController(pointerLocation: { CGPoint(x: 250, y: height - 200) })
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { _ in }, onCancel: {})
        #expect(presented)
        controller.attachSnapRegions(twoWindowResolver())
        let panel = try primaryOverlay()
        let first = NSPoint(x: 250, y: height - 200)
        let second = NSPoint(x: 750, y: height - 200)

        // Pending overlay: clear inside the snap region, dimmed (48 % black) outside it.
        #expect(try renderedAlpha(panel, at: first) == 0)
        #expect(try renderedAlpha(panel, at: second) > 100)

        try send(.mouseMoved, at: second, to: panel)

        #expect(try renderedAlpha(panel, at: second) == 0)
        #expect(try renderedAlpha(panel, at: first) > 100)
    }

    @Test("a replacement's window list does not reach the overlay it may roll back to")
    func rollbackKeepsPreviousSnapRegions() throws {
        let screen = try primaryScreen()
        let height = screen.frame.height
        var selections: [CGRect] = []
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { selections.append($0.screenFrame) }, onCancel: {})
        #expect(presented)
        let committed = controller.commit(displays: [makeDisplay(id: try displayID(screen), screen: screen)])
        #expect(committed)
        controller.attachSnapRegions(resolver(windows: [CGRect(x: 100, y: 100, width: 300, height: 200)]))
        let previous = try primaryOverlay()

        let replacing = controller.presentPending(onSelection: { _ in }, onCancel: {})
        #expect(replacing)
        controller.attachSnapRegions(resolver(windows: [CGRect(x: 600, y: 100, width: 300, height: 200)]))
        controller.rollback()

        // The restored overlay still snaps with its own list: no window there, so the display.
        try click(previous, from: NSPoint(x: 750, y: height - 200), to: NSPoint(x: 750, y: height - 200))
        #expect(selections == [screen.frame])
    }

    @Test("pointer jitter of up to three points while pressed is still a click")
    func jitterWithinThresholdIsClick() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, selections) = try committedSnapOverlay()
        defer { controller.close() }
        try send(.leftMouseDown, at: NSPoint(x: 250, y: height - 200), to: panel)
        // Physical jitter arrives as several small drag events.
        try send(.leftMouseDragged, at: NSPoint(x: 251, y: height - 200), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 252, y: height - 200), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 253, y: height - 200), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: 253, y: height - 200), to: panel)
        #expect(selections.frames == [CGRect(x: 100, y: height - 300, width: 300, height: 200)])
    }

    @Test("a press moved just over three points draws a rectangle")
    func moveJustOverThresholdDrags() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, selections) = try committedSnapOverlay()
        defer { controller.close() }
        try send(.leftMouseDown, at: NSPoint(x: 250, y: height - 200), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 252.5, y: height - 197.5), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: 252.5, y: height - 197.5), to: panel)
        #expect(selections.frames == [CGRect(x: 250, y: height - 200, width: 2.5, height: 2.5)])
    }

    @Test("while dragging the rectangle is drawn instead of the snap region")
    func dragDrawsRectangleWhileDragging() throws {
        let height = try primaryScreen().frame.height
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { _ in }, onCancel: {})
        #expect(presented)
        controller.attachSnapRegions(twoWindowResolver())
        let panel = try primaryOverlay()
        try send(.leftMouseDown, at: NSPoint(x: 250, y: height - 200), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 290, y: height - 170), to: panel)
        // Before release: clear inside the dragged rectangle, dimmed elsewhere in window A.
        #expect(try renderedAlpha(panel, at: NSPoint(x: 270, y: height - 185)) == 0)
        #expect(try renderedAlpha(panel, at: NSPoint(x: 150, y: height - 250)) > 100)
    }

    @Test("a drag passing three points in small steps stops showing the snap region")
    func smallStepDragStopsSnapping() throws {
        let height = try primaryScreen().frame.height
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { _ in }, onCancel: {})
        #expect(presented)
        controller.attachSnapRegions(twoWindowResolver())
        let panel = try primaryOverlay()
        try send(.leftMouseDown, at: NSPoint(x: 250, y: height - 200), to: panel)
        // 1.98 pt and then 3.96 pt from the press, each step under 3 pt.
        try send(.leftMouseDragged, at: NSPoint(x: 251.4, y: height - 198.6), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 252.8, y: height - 197.2), to: panel)
        // Before release, window A outside the tiny rectangle is dimmed again.
        #expect(try renderedAlpha(panel, at: NSPoint(x: 150, y: height - 250)) > 100)
    }

    @Test("a release far from the press is a rectangle even without drag events")
    func farReleaseWithoutDragEventsDrags() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, selections) = try committedSnapOverlay()
        defer { controller.close() }
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 300, y: height - 150))
        #expect(selections.frames == [CGRect(x: 250, y: height - 200, width: 50, height: 50)])
    }

    @Test("a clicked region stays put while the pointer moves on")
    func clickedRegionDoesNotFollowPointer() throws {
        let height = try primaryScreen().frame.height
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { _ in }, onCancel: {})
        #expect(presented)
        controller.attachSnapRegions(twoWindowResolver())
        let panel = try primaryOverlay()
        let first = NSPoint(x: 250, y: height - 200)
        let second = NSPoint(x: 750, y: height - 200)
        try click(panel, from: first, to: first)
        try send(.mouseMoved, at: second, to: panel)
        #expect(try renderedAlpha(panel, at: first) == 0)
        #expect(try renderedAlpha(panel, at: second) > 100)
    }

    @Test("a clicked region is handed over as its physical pixel corners")
    func clickedRegionMapsToPixels() throws {
        let screen = try primaryScreen()
        let height = screen.frame.height
        let scale = screen.backingScaleFactor
        var corners: [(CapturePoint, CapturePoint)] = []
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let presented = controller.presentPending(onSelection: { corners.append(($0.start, $0.end)) }, onCancel: {})
        #expect(presented)
        let committed = controller.commit(displays: [
            makeDisplay(id: try displayID(screen), screen: screen, pixelScale: scale)
        ])
        #expect(committed)
        controller.attachSnapRegions(twoWindowResolver())
        try click(try primaryOverlay(), from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        // Window (100, 100, 300, 200) top-left: corners (100, 300) and (400, 100) in points, × scale.
        let (start, end) = try #require(corners.first)
        #expect(corners.count == 1)
        // Pixel mapping divides by the display size; allow rounding on displays of any size.
        #expect(abs(start.x - 100 * scale) < 0.001 && abs(start.y - 300 * scale) < 0.001)
        #expect(abs(end.x - 400 * scale) < 0.001 && abs(end.y - 100 * scale) < 0.001)
    }

    // Confirmed selection adjustment (v1-core::REQ-007). Window A is (100, H − 300, 300, 200) in local
    // AppKit points; expected frames are computed by hand from it. The display has real pixel sizes so
    // the two-pixel minimum applies as on a screen. Cursor shapes are checked on the installed build, and
    // withdrawing a selection when a new one starts on another display needs two displays (installed build).
    @Test("a confirmed selection shows handles at its corners and edge midpoints")
    func confirmedSelectionShowsHandles() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, _) = try committedSnapOverlay(pixelScale: try primaryScreen().backingScaleFactor)
        defer { controller.close() }
        // Just outside the top-left corner: dimmed before, covered by the opaque handle after.
        let outsideCorner = NSPoint(x: 97.5, y: height - 97.5)
        #expect(try renderedAlpha(panel, at: outsideCorner) < 200)
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        for point in [outsideCorner, NSPoint(x: 250, y: height - 97.5), NSPoint(x: 402.5, y: height - 97.5),
                      NSPoint(x: 402.5, y: height - 200), NSPoint(x: 402.5, y: height - 302.5),
                      NSPoint(x: 250, y: height - 302.5), NSPoint(x: 97.5, y: height - 302.5),
                      NSPoint(x: 97.5, y: height - 200)] {
            #expect(try renderedAlpha(panel, at: point) == 255)
        }
    }

    @Test("corner handles move two sides and edge handles one")
    func handlesResizeSelection() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, log) = try committedSnapOverlay(pixelScale: try primaryScreen().backingScaleFactor)
        defer { controller.close() }
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        try drag(panel, from: NSPoint(x: 400, y: height - 300), to: NSPoint(x: 300, y: height - 250))
        try drag(panel, from: NSPoint(x: 200, y: height - 100), to: NSPoint(x: 200, y: height - 70))
        #expect(log.frames == [
            CGRect(x: 100, y: height - 300, width: 300, height: 200),
            CGRect(x: 100, y: height - 250, width: 200, height: 150),
            CGRect(x: 100, y: height - 250, width: 200, height: 180),
        ])
    }

    @Test("dragging a side past the opposite side flips the selection")
    func handlePastOppositeSideFlips() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, log) = try committedSnapOverlay(pixelScale: try primaryScreen().backingScaleFactor)
        defer { controller.close() }
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        try drag(panel, from: NSPoint(x: 100, y: height - 200), to: NSPoint(x: 450, y: height - 200))
        #expect(log.frames.last == CGRect(x: 400, y: height - 300, width: 50, height: 200))
    }

    @Test("dragging inside moves the selection and keeps it on the display")
    func dragInsideMovesSelection() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, log) = try committedSnapOverlay(pixelScale: try primaryScreen().backingScaleFactor)
        defer { controller.close() }
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        try drag(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 290, y: height - 220))
        try drag(panel, from: NSPoint(x: 250, y: height - 220), to: NSPoint(x: -750, y: height - 220))
        #expect(log.frames == [
            CGRect(x: 100, y: height - 300, width: 300, height: 200),
            CGRect(x: 140, y: height - 320, width: 300, height: 200),
            CGRect(x: 0, y: height - 320, width: 300, height: 200),
        ])
        // The toolbar was told about every intermediate frame.
        #expect(log.changes.contains(CGRect(x: 140, y: height - 320, width: 300, height: 200)))
    }

    @Test("a press outside a confirmed selection starts a new one")
    func pressOutsideStartsNewSelection() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, log) = try committedSnapOverlay(pixelScale: try primaryScreen().backingScaleFactor)
        defer { controller.close() }
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        try click(panel, from: NSPoint(x: 750, y: height - 200), to: NSPoint(x: 750, y: height - 200))
        #expect(log.changes.contains(nil))
        #expect(log.frames.last == CGRect(x: 600, y: height - 300, width: 300, height: 200))
    }

    @Test("a selection under two pixels gets no handles, so a press on it starts a new one")
    func tinySelectionHasNoHandles() throws {
        let screen = try primaryScreen()
        let height = screen.frame.height
        let (controller, panel, log) = try committedSnapOverlay(pixelScale: screen.backingScaleFactor)
        defer { controller.close() }
        // Past the drag threshold but only 0.25 pt tall: under two physical pixels at any scale here.
        try drag(panel, from: NSPoint(x: 500, y: height - 500), to: NSPoint(x: 510, y: height - 499.75))
        #expect(log.frames.count == 1)
        try click(panel, from: NSPoint(x: 500, y: height - 500), to: NSPoint(x: 500, y: height - 500))
        #expect(log.frames.last == screen.frame)
    }

    @Test("a selection that the crop rounds up to two pixels gets handles")
    func selectionRoundedUpToTwoPixelsHasHandles() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, log) = try committedSnapOverlay(pixelScale: 2)
        defer { controller.close() }
        // 0.75 pt at 2 px per point is 1.5 px straddling a pixel row, which the crop takes as 2 px.
        try drag(panel, from: NSPoint(x: 500, y: height - 500), to: NSPoint(x: 510, y: height - 499.25))
        // Its bottom-left handle: a press there adjusts the selection instead of starting a new one.
        try click(panel, from: NSPoint(x: 500, y: height - 500), to: NSPoint(x: 500, y: height - 500))
        #expect(log.frames.last == CGRect(x: 500, y: height - 500, width: 10, height: 0.75))
    }

    @Test("handles are filled with the surface colour of the current appearance")
    func handleFillFollowsAppearance() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, _) = try committedSnapOverlay(pixelScale: try primaryScreen().backingScaleFactor)
        defer { controller.close() }
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        // Inside the top-left handle, clear of its 1 pt outline.
        let fill = NSPoint(x: 99.5, y: height - 101.5)
        panel.appearance = NSAppearance(named: .aqua)
        #expect(try renderedRGBA(panel, at: fill)[0] > 230)
        panel.appearance = NSAppearance(named: .darkAqua)
        #expect(try renderedRGBA(panel, at: fill)[0] < 60)
    }

    @Test("an adjustment under two pixels snaps back to the previous selection")
    func tinyAdjustmentSnapsBack() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, log) = try committedSnapOverlay(pixelScale: try primaryScreen().backingScaleFactor)
        defer { controller.close() }
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        try drag(panel, from: NSPoint(x: 400, y: height - 200), to: NSPoint(x: 100.4, y: height - 200))
        #expect(log.frames == [CGRect(x: 100, y: height - 300, width: 300, height: 200)])
        #expect(log.changes.last == CGRect(x: 100, y: height - 300, width: 300, height: 200))
    }

    // A modal session would put an alert under the overlay in the sandboxed app (layer 8 under 1000);
    // this test process keeps the level, so which layer it lands on is checked on the installed build.
    @Test("an alert over the overlay is a sheet of it and blocks selections until it ends")
    func alertIsSheetOfOverlay() async throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, log) = try committedSnapOverlay()
        defer { controller.close() }
        let alert = NSAlert()
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Cancel")
        let shown = Task { await controller.presentAlert(alert) }
        for _ in 0..<100 where panel.attachedSheet == nil { await Task.yield() }
        #expect(panel.attachedSheet === alert.window)
        panel.endSheet(alert.window, returnCode: .alertSecondButtonReturn)
        #expect(await shown.value == .alertSecondButtonReturn)
        // AppKit drops presses while the sheet is still sliding away; wait until it is detached.
        for _ in 0..<500 where panel.attachedSheet != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(panel.attachedSheet == nil)
        // The overlay has the keyboard again, so Esc and the next press reach it.
        #expect(panel.isKeyWindow)
        // Window A, once the alert has ended.
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        #expect(log.frames == [CGRect(x: 100, y: height - 300, width: 300, height: 200)])
    }

    @Test("presses start nothing while selection is paused, and work again after")
    func pausedSelectionIgnoresPresses() throws {
        let height = try primaryScreen().frame.height
        let (controller, panel, log) = try committedSnapOverlay()
        defer { controller.close() }
        controller.setSelectionEnabled(false)
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        try drag(panel, from: NSPoint(x: 500, y: height - 500), to: NSPoint(x: 600, y: height - 400))
        #expect(log.frames.isEmpty)
        // A panel shown meanwhile takes the keyboard, as the save panel does.
        let other = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
        other.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        other.makeKeyAndOrderFront(nil)
        defer { other.orderOut(nil) }
        #expect(!panel.isKeyWindow)
        controller.setSelectionEnabled(true)
        #expect(panel.isKeyWindow)
        try click(panel, from: NSPoint(x: 250, y: height - 200), to: NSPoint(x: 250, y: height - 200))
        #expect(log.frames == [CGRect(x: 100, y: height - 300, width: 300, height: 200)])
    }
}

@MainActor
private func visibleOverlays() -> [NSWindow] {
    NSApp.windows.filter { $0.isVisible && $0.level == .screenSaver }
}

private func makeDisplay(
    id: UInt32,
    screen: NSScreen,
    pixelScale: CGFloat? = nil
) -> FrozenCaptureDisplay {
    let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return FrozenCaptureDisplay(
        geometry: CaptureDisplayGeometry(
            displayID: id,
            logicalX: screen.frame.minX,
            logicalY: screen.frame.minY,
            logicalWidth: screen.frame.width,
            logicalHeight: screen.frame.height,
            pixelWidth: pixelScale.map { Int(screen.frame.width * $0) } ?? 2,
            pixelHeight: pixelScale.map { Int(screen.frame.height * $0) } ?? 2,
            rotationDegrees: 0
        ),
        frame: FrozenDisplayFrame(image: context.makeImage()!)
    )
}

@MainActor
private func present(_ controller: FrozenCaptureOverlayController) -> Bool {
    controller.presentPending(onSelection: { _ in }, onCancel: {})
}

@MainActor
private func primaryScreen() throws -> NSScreen {
    try #require(NSScreen.screens.first)
}

private func displayID(_ screen: NSScreen) throws -> UInt32 {
    try #require(
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    )
}

@MainActor
private func primaryOverlay() throws -> NSWindow {
    let screen = try primaryScreen()
    return try #require(visibleOverlays().first { $0.frame == screen.frame })
}

private func twoWindowResolver() -> CaptureSnapRegionResolver {
    resolver(windows: [
        CGRect(x: 100, y: 100, width: 300, height: 200),
        CGRect(x: 600, y: 100, width: 300, height: 200),
    ])
}

private func resolver(windows bounds: [CGRect]) -> CaptureSnapRegionResolver {
    let windows = bounds.map {
        CaptureWindowSnapshotEntry(ownerProcessID: 4242, layer: 0, alpha: 1, isOnScreen: true, bounds: $0)
    }
    return CaptureSnapRegionResolver(
        snapshot: CaptureWindowSnapshot(windows: windows, dockProcessID: nil),
        excludedProcessID: ProcessInfo.processInfo.processIdentifier
    )
}

@MainActor
private func send(_ type: NSEvent.EventType, at point: NSPoint, to window: NSWindow) throws {
    window.sendEvent(try #require(NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: 1, pressure: 1
    )))
}

@MainActor
private func click(_ window: NSWindow, from down: NSPoint, to up: NSPoint) throws {
    try send(.leftMouseDown, at: down, to: window)
    try send(.leftMouseUp, at: up, to: window)
}

/// Red, green, blue and alpha the overlay renders at one point of its window.
@MainActor
private func renderedRGBA(_ window: NSWindow, at point: NSPoint) throws -> [UInt8] {
    let layer = try #require(window.contentView?.layer)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.translateBy(x: -point.x, y: -point.y)
    layer.render(in: context)
    let data = try #require(context.data)
    return (0..<4).map { data.load(fromByteOffset: $0, as: UInt8.self) }
}

/// Alpha the overlay renders at one point of its window.
@MainActor
private func renderedAlpha(_ window: NSWindow, at point: NSPoint) throws -> UInt8 {
    try renderedRGBA(window, at: point)[3]
}

/// Selections made on an overlay, collected by reference so tests can read them after events.
@MainActor
private final class SelectionLog {
    var frames: [CGRect] = []
    /// Frames reported while a confirmed selection is adjusted; `nil` when a press outside discards it.
    var changes: [CGRect?] = []
}

/// A committed overlay on the primary display with the two-window snap regions attached.
@MainActor
private func committedSnapOverlay(
    pixelScale: CGFloat? = nil
) throws -> (FrozenCaptureOverlayController, NSWindow, SelectionLog) {
    let screen = try primaryScreen()
    let log = SelectionLog()
    let controller = FrozenCaptureOverlayController()
    let presented = controller.presentPending(
        onSelection: { log.frames.append($0.screenFrame) },
        onCancel: {},
        onSelectionChanging: { frame, _ in log.changes.append(frame) }
    )
    #expect(presented)
    let committed = controller.commit(displays: [
        makeDisplay(id: try displayID(screen), screen: screen, pixelScale: pixelScale)
    ])
    #expect(committed)
    controller.attachSnapRegions(twoWindowResolver())
    return (controller, try primaryOverlay(), log)
}



/// Presses, drags once and releases, as a pointer drag arrives.
@MainActor
private func drag(_ window: NSWindow, from start: NSPoint, to end: NSPoint) throws {
    try send(.leftMouseDown, at: start, to: window)
    try send(.leftMouseDragged, at: end, to: window)
    try send(.leftMouseUp, at: end, to: window)
}
