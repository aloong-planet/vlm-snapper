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

    @Test("a failure alert stays visible above a retained overlay")
    func failureAlertStaysAboveRetainedOverlay() throws {
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
        let alert = NSAlert()

        controller.prepareFailurePresentation(alert)

        #expect(alert.window.level.rawValue > NSWindow.Level.screenSaver.rawValue)
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

/// Alpha the overlay renders at one point of its window.
@MainActor
private func renderedAlpha(_ window: NSWindow, at point: NSPoint) throws -> UInt8 {
    let layer = try #require(window.contentView?.layer)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.translateBy(x: -point.x, y: -point.y)
    layer.render(in: context)
    return try #require(context.data).load(fromByteOffset: 3, as: UInt8.self)
}

/// Selections made on an overlay, collected by reference so tests can read them after events.
@MainActor
private final class SelectionLog {
    var frames: [CGRect] = []
}

/// A committed overlay on the primary display with the two-window snap regions attached.
@MainActor
private func committedSnapOverlay() throws -> (FrozenCaptureOverlayController, NSWindow, SelectionLog) {
    let screen = try primaryScreen()
    let log = SelectionLog()
    let controller = FrozenCaptureOverlayController()
    let presented = controller.presentPending(onSelection: { log.frames.append($0.screenFrame) }, onCancel: {})
    #expect(presented)
    let committed = controller.commit(displays: [makeDisplay(id: try displayID(screen), screen: screen)])
    #expect(committed)
    controller.attachSnapRegions(twoWindowResolver())
    return (controller, try primaryOverlay(), log)
}

