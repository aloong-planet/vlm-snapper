import AppKit
import SwiftUI
import XCTest
@testable import VLMSnapperUI

// Native responder events test the production view, not physical mouse/trackpad
// delivery. Installed-app device feel and inertial gestures need manual acceptance.
@MainActor
final class HistoryImageZoomTests: XCTestCase {
    func testWheelZoomsAroundPointerAndReverses() throws {
        try withPreview { scroll, host in
            let initial = scroll.magnification
            let document = try XCTUnwrap(scroll.documentView)
            let renderedImage = scroll.convert(document.bounds, from: document)
            let viewport = scroll.convert(scroll.contentView.bounds, from: scroll.contentView)
            // The preview follows the available display size, including CI's
            // smaller desktop. Verify fit geometry, not a machine-specific scale.
            XCTAssertEqual(renderedImage.width, viewport.width - 40, accuracy: 1)
            XCTAssertLessThanOrEqual(renderedImage.height, viewport.height)
            try capture(host, name: "fit")
            let point = NSPoint(x: scroll.contentView.bounds.midX + 80, y: scroll.contentView.bounds.midY)
            let windowPoint = scroll.contentView.convert(point, to: nil)
            let event = try wheel(delta: 2, at: windowPoint, window: scroll.window!)
            scroll.scrollWheel(with: event)
            XCTAssertGreaterThan(scroll.magnification, initial)
            let after = scroll.contentView.convert(point, to: nil)
            XCTAssertEqual(after.x, windowPoint.x, accuracy: 1)
            XCTAssertEqual(after.y, windowPoint.y, accuracy: 1)
            try capture(host, name: "zoom")
            scroll.scrollWheel(with: try wheel(delta: -2, at: windowPoint, window: scroll.window!))
            XCTAssertEqual(scroll.magnification, initial, accuracy: 0.001)
        }
    }

    func testZoomLimitsAndIgnoredEvents() throws {
        try withPreview { scroll, _ in
            let window = try XCTUnwrap(scroll.window)
            let point = scroll.contentView.convert(NSPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY), to: nil)
            let initial = scroll.magnification
            scroll.scrollWheel(with: try wheel(delta: 0, at: point, window: window))
            XCTAssertEqual(scroll.magnification, initial)
            let momentum = try wheel(delta: 3, at: point, window: window, momentum: true)
            XCTAssertFalse(momentum.momentumPhase.isEmpty)
            scroll.scrollWheel(with: momentum)
            XCTAssertEqual(scroll.magnification, initial)
            for _ in 0..<40 { scroll.scrollWheel(with: try wheel(delta: 100, at: point, window: window)) }
            XCTAssertEqual(scroll.magnification, 8, accuracy: 0.001)
            for _ in 0..<60 { scroll.scrollWheel(with: try wheel(delta: -100, at: point, window: window)) }
            XCTAssertEqual(scroll.magnification, 0.05, accuracy: 0.001)
        }
    }

    func testDraggingPansMagnifiedImageWithoutChangingZoom() throws {
        try withPreview(height: 1600) { scroll, _ in
            let window = try XCTUnwrap(scroll.window)
            let point = scroll.contentView.convert(NSPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY), to: nil)
            for _ in 0..<10 { scroll.scrollWheel(with: try wheel(delta: 100, at: point, window: window)) }
            let scale = scroll.magnification, origin = scroll.contentView.bounds.origin
            let document = try XCTUnwrap(scroll.documentView)
            let windowNumber = window.windowNumber
            func mouse(_ type: NSEvent.EventType, _ p: NSPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0,
                    windowNumber: windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            document.mouseDown(with: try mouse(.leftMouseDown, point))
            let end = NSPoint(x: point.x + 50, y: point.y + 60)
            document.mouseDragged(with: try mouse(.leftMouseDragged, end))
            document.mouseUp(with: try mouse(.leftMouseUp, end))
            XCTAssertEqual(scroll.contentView.bounds.minX, origin.x - 50 / scale, accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.minY, origin.y - 60 / scale, accuracy: 1)
            XCTAssertEqual(scroll.magnification, scale)
        }
    }

    private func withPreview(height: Int = 300, _ body: (NSScrollView, NSHostingView<HistoryImagePreview>) throws -> Void) throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: height).fill()
        ("Original screenshot — wheel zoom" as NSString).draw(at: NSPoint(x: 40, y: 140),
            withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 1200, height: height))
        image.addRepresentation(bitmap)
        let host = NSHostingView(rootView: HistoryImagePreview(image: image))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
        scroll.layoutSubtreeIfNeeded()
        try body(scroll, host)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func capture(_ host: NSView, name: String) throws {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
            FileManager.default.temporaryDirectory.appendingPathComponent("history-zoom-\(name).png"))
    }

    private func wheel(delta: Int32, at point: NSPoint, window: NSWindow, momentum: Bool = false) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
            wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        let screen = window.convertPoint(toScreen: point)
        event.location = CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screen.y)
        if momentum { event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2) }
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }
}
