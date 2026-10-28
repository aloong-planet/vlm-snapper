import CoreGraphics

/// One on-screen window as the window server lists it, in global top-left coordinates
/// (the space of `CaptureDisplayGeometry.logicalX/Y`).
public struct CaptureWindowSnapshotEntry: Sendable, Equatable {
    public let ownerProcessID: Int32
    public let layer: Int
    public let alpha: Double
    public let isOnScreen: Bool
    public let bounds: CGRect

    public init(ownerProcessID: Int32, layer: Int, alpha: Double, isOnScreen: Bool, bounds: CGRect) {
        self.ownerProcessID = ownerProcessID
        self.layer = layer
        self.alpha = alpha
        self.isOnScreen = isOnScreen
        self.bounds = bounds
    }
}

/// The window list taken when a capture starts, front to back.
public struct CaptureWindowSnapshot: Sendable, Equatable {
    public let windows: [CaptureWindowSnapshotEntry]
    public let dockProcessID: Int32?

    public init(windows: [CaptureWindowSnapshotEntry], dockProcessID: Int32?) {
        self.windows = windows
        self.dockProcessID = dockProcessID
    }
}

/// Takes the window list for one capture; `nil` when it cannot be read.
public protocol CaptureWindowListing: Sendable {
    func captureWindowSnapshot() async -> CaptureWindowSnapshot?
}

/// A display in global top-left coordinates; the visible frame excludes the menu bar and a
/// Dock that reserves space.
public struct CaptureSnapDisplay: Sendable, Equatable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let pointPixelScale: Double

    public init(frame: CGRect, visibleFrame: CGRect, pointPixelScale: Double) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.pointPixelScale = pointPixelScale
    }
}

/// Finds the snap region under a point: the topmost window as a whole, the Dock strip as one
/// region, or the whole display over the desktop (ADR-0014).
public struct CaptureSnapRegionResolver: Sendable {
    /// Pop-up menus sit at layer 101; anything higher is a system overlay (input method
    /// candidates, the cursor, screen savers including VLMSnapper's own overlay).
    private static let highestSnappableLayer = 102

    private let snapshot: CaptureWindowSnapshot
    private let excludedProcessID: Int32

    public init(snapshot: CaptureWindowSnapshot, excludedProcessID: Int32) {
        self.snapshot = snapshot
        self.excludedProcessID = excludedProcessID
    }

    public func region(at point: CGPoint, on display: CaptureSnapDisplay) -> CGRect {
        for window in snapshot.windows {
            guard window.ownerProcessID != excludedProcessID,
                  window.alpha > 0,
                  window.isOnScreen,
                  window.layer <= Self.highestSnappableLayer,
                  window.bounds.contains(point) else { continue }
            if window.ownerProcessID == snapshot.dockProcessID {
                // The Dock's window covers the whole display; only its reserved strip counts.
                if let strip = dockStrip(on: display), strip.contains(point) { return strip }
                continue
            }
            let clipped = window.bounds.intersection(display.frame)
            guard clipped.width * display.pointPixelScale >= 2,
                  clipped.height * display.pointPixelScale >= 2 else { continue }
            return clipped
        }
        return display.frame
    }

    private func dockStrip(on display: CaptureSnapDisplay) -> CGRect? {
        let frame = display.frame
        let visible = display.visibleFrame
        if visible.maxY < frame.maxY {
            return CGRect(x: frame.minX, y: visible.maxY, width: frame.width, height: frame.maxY - visible.maxY)
        }
        if visible.minX > frame.minX {
            return CGRect(x: frame.minX, y: visible.minY, width: visible.minX - frame.minX, height: frame.maxY - visible.minY)
        }
        if visible.maxX < frame.maxX {
            return CGRect(x: visible.maxX, y: visible.minY, width: frame.maxX - visible.maxX, height: frame.maxY - visible.minY)
        }
        return nil
    }
}
