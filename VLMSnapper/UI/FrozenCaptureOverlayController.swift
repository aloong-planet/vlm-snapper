import AppKit
import VLMSnapperCore

@MainActor
public final class FrozenCaptureOverlayController {
    public struct Selection {
        public let displayID: UInt32
        public let start: CapturePoint
        public let end: CapturePoint
        public let screenFrame: CGRect
        public let screen: NSScreen
    }

    private var panels: [CaptureOverlayPanel] = []

    public init() {}

    public func show(
        displays: [FrozenCaptureDisplay],
        onSelection: @escaping @MainActor (Selection) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        close()
        let screensByDisplayID: [UInt32: NSScreen] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen
                -> (UInt32, NSScreen)? in
                guard let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber else {
                    return nil
                }
                return (number.uint32Value, screen)
            }
        )
        for display in displays {
            guard let screen = screensByDisplayID[display.geometry.displayID] else {
                continue
            }
            let panel = CaptureOverlayPanel(frame: screen.frame)
            let view = CaptureOverlayView(
                display: display,
                onSelection: { [weak panel] start, end, localFrame in
                    guard let panel else { return }
                    let globalFrame = CGRect(
                        x: panel.frame.minX + localFrame.minX,
                        y: panel.frame.minY + localFrame.minY,
                        width: localFrame.width,
                        height: localFrame.height
                    )
                    onSelection(
                        Selection(
                            displayID: display.geometry.displayID,
                            start: start,
                            end: end,
                            screenFrame: globalFrame,
                            screen: screen
                        )
                    )
                },
                onCancel: onCancel
            )
            panel.contentView = view
            panels.append(panel)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    public func close() {
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
    }
}

private final class CaptureOverlayPanel: NSPanel {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

private final class CaptureOverlayView: NSView {
    private let image: NSImage
    private let geometry: CaptureDisplayGeometry
    private let onSelection: @MainActor (CapturePoint, CapturePoint, CGRect) -> Void
    private let onCancel: @MainActor () -> Void
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    init(
        display: FrozenCaptureDisplay,
        onSelection: @escaping @MainActor (CapturePoint, CapturePoint, CGRect) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        image = NSImage(
            cgImage: display.frame.image,
            size: NSSize(
                width: display.geometry.logicalWidth,
                height: display.geometry.logicalHeight
            )
        )
        geometry = display.geometry
        self.onSelection = onSelection
        self.onCancel = onCancel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        guard let selectionRect else {
            NSColor.black.withAlphaComponent(0.48).setFill()
            bounds.fill()
            return
        }

        let dimmed = NSBezierPath(rect: bounds)
        dimmed.appendRect(selectionRect)
        dimmed.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill()
        dimmed.fill()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        dragCurrent = end
        needsDisplay = true
        guard let selectionRect else { return }
        onSelection(
            CaptureCoordinateMapper.pixelPoint(
                fromLocalAppKitPoint: CapturePoint(x: dragStart.x, y: dragStart.y),
                geometry: geometry
            ),
            CaptureCoordinateMapper.pixelPoint(
                fromLocalAppKitPoint: CapturePoint(x: end.x, y: end.y),
                geometry: geometry
            ),
            selectionRect
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }
}
