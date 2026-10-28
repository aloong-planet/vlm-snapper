import AppKit
import QuartzCore
import VLMSnapperCore

/// Selection overlays shown in two phases: a pending overlay covers every
/// display as soon as a capture starts, and `commit` shows each display's frozen
/// frame in that same panel once the freeze finishes. The freeze filter excludes
/// VLMSnapper's own windows, which keeps the pending overlay out of the frame.
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
    private var pendingPanels: [CaptureOverlayPanel] = []

    /// Displays covered by the current frozen overlay; a pending overlay does
    /// not change this until it is committed.
    public var presentedDisplayIDs: Set<UInt32> {
        Set(panels.map(\.displayID))
    }

    public init() {}

    /// Covers every connected display before frozen frames exist. The current
    /// overlay is hidden but kept until `commit` retires it or `rollback`
    /// shows it again.
    @discardableResult
    public func presentPending(
        onSelection: @escaping @MainActor (Selection) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) -> Bool {
        retire(pendingPanels)
        pendingPanels = NSScreen.screens.compactMap { screen in
            guard let displayID = screen.displayID else { return nil }
            let panel = CaptureOverlayPanel(displayID: displayID, screen: screen)
            panel.contentView = CaptureOverlayView(
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
                            displayID: panel.displayID,
                            start: start,
                            end: end,
                            screenFrame: globalFrame,
                            screen: panel.overlayScreen
                        )
                    )
                },
                onCancel: onCancel
            )
            return panel
        }.sorted { $0.displayID < $1.displayID }
        guard !pendingPanels.isEmpty else { return false }
        // Order the new panels in before hiding the old ones so the desktop never flashes.
        for panel in pendingPanels {
            panel.orderFrontRegardless()
        }
        pendingPanels.last?.makeKey()
        for panel in panels {
            panel.orderOut(nil)
        }
        return true
    }

    /// Shows each frozen frame in its pending panel and retires the previous
    /// overlay. Pending panels without a frame are withdrawn. Returns `false`
    /// and changes nothing when no frame matches a pending panel.
    @discardableResult
    public func commit(displays: [FrozenCaptureDisplay]) -> Bool {
        let screens = Dictionary(
            NSScreen.screens.compactMap { screen in screen.displayID.map { ($0, screen) } },
            uniquingKeysWith: { first, _ in first }
        )
        let framesByDisplayID = Dictionary(
            displays.map { ($0.geometry.displayID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let framed = pendingPanels.filter {
            framesByDisplayID[$0.displayID] != nil && screens[$0.displayID] != nil
        }
        guard !framed.isEmpty else { return false }
        let framedIDs = Set(framed.map(ObjectIdentifier.init))
        let withdrawn = pendingPanels.filter { !framedIDs.contains(ObjectIdentifier($0)) }
        let retired = panels
        pendingPanels.removeAll()
        panels = framed
        retire(withdrawn + retired)
        for panel in framed {
            guard let display = framesByDisplayID[panel.displayID],
                  let screen = screens[panel.displayID] else { continue }
            panel.place(on: screen)
            panel.overlayView?.attach(display)
        }
        if !framed.contains(where: \.isKeyWindow) {
            framed.last?.makeKey()
        }
        return true
    }

    /// Withdraws the pending overlay and shows the previous overlay again.
    public func rollback() {
        guard !pendingPanels.isEmpty else { return }
        let withdrawn = pendingPanels
        pendingPanels.removeAll()
        for panel in panels {
            panel.orderFrontRegardless()
        }
        panels.last?.makeKey()
        retire(withdrawn)
    }

    public func invalidateDisplays(_ invalidated: [UInt32]) {
        let invalidatedIDs = Set(invalidated)
        let retired = panels.filter { invalidatedIDs.contains($0.displayID) }
        panels.removeAll { invalidatedIDs.contains($0.displayID) }
        let lostKeyWindow = retired.contains { $0.isKeyWindow }
        retire(retired)
        if lostKeyWindow { panels.last?.makeKey() }
    }

    /// Withdraws every overlay, pending or frozen.
    public func close() {
        let retired = pendingPanels + panels
        pendingPanels.removeAll()
        panels.removeAll()
        retire(retired)
    }

    public func prepareFailurePresentation(_ alert: NSAlert) {
        guard !panels.isEmpty else { return }
        alert.window.level = NSWindow.Level(
            rawValue: NSWindow.Level.screenSaver.rawValue + 1
        )
    }

    private func retire(_ panels: [CaptureOverlayPanel]) {
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
}

private extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }
}

private final class CaptureOverlayPanel: NSPanel {
    let displayID: UInt32
    private(set) var overlayScreen: NSScreen

    init(displayID: UInt32, screen: NSScreen) {
        self.displayID = displayID
        overlayScreen = screen
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        // Transparent until the frozen frame arrives: the pending overlay dims
        // the live screen, then the frozen frame covers it at native resolution.
        isOpaque = false
        backgroundColor = .clear
        // A transparent window lets clicks through where it is fully clear, as
        // inside a selection drawn before the frame arrives; keep them here.
        ignoresMouseEvents = false
        // The default window-open animation starts the panel slightly smaller than
        // the screen and grows it over several frames; the overlay must cover at once.
        animationBehavior = .none
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    var overlayView: CaptureOverlayView? {
        contentView as? CaptureOverlayView
    }

    func place(on screen: NSScreen) {
        overlayScreen = screen
        if frame != screen.frame {
            setFrame(screen.frame, display: false)
        }
    }
}

/// Renders with layers: the frozen frame is a layer's contents, so dragging only
/// rebuilds two small paths instead of redrawing a full-resolution frame.
private final class CaptureOverlayView: NSView {
    private let onSelection: @MainActor (CapturePoint, CapturePoint, CGRect) -> Void
    private let onCancel: @MainActor () -> Void
    private let frameLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var geometry: CaptureDisplayGeometry?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    // A drag released before the frozen frame arrived; finished by `attach`.
    private var completedBeforeFrame = false

    init(
        onSelection: @escaping @MainActor (CapturePoint, CapturePoint, CGRect) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.onSelection = onSelection
        self.onCancel = onCancel
        super.init(frame: .zero)
        wantsLayer = true
        frameLayer.contentsGravity = .resize
        frameLayer.magnificationFilter = .nearest
        frameLayer.minificationFilter = .nearest
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1
        for sublayer in [frameLayer, dimLayer, borderLayer] {
            layer?.addSublayer(sublayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var acceptsFirstResponder: Bool { true }

    func attach(_ display: FrozenCaptureDisplay) {
        geometry = display.geometry
        updateLayers { frameLayer.contents = display.frame.image }
        if completedBeforeFrame, let dragStart, let dragCurrent {
            completedBeforeFrame = false
            finishSelection(from: dragStart, to: dragCurrent)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayers()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 1
        updateLayers {
            for sublayer in [frameLayer, dimLayer, borderLayer] {
                sublayer.contentsScale = scale
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayers()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        completedBeforeFrame = false
        updateLayers()
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        updateLayers()
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        dragCurrent = end
        updateLayers()
        guard geometry != nil else {
            completedBeforeFrame = true
            return
        }
        finishSelection(from: dragStart, to: end)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    private func finishSelection(from start: CGPoint, to end: CGPoint) {
        guard let geometry, let selectionRect else { return }
        onSelection(
            CaptureCoordinateMapper.pixelPoint(
                fromLocalAppKitPoint: CapturePoint(x: start.x, y: start.y),
                geometry: geometry
            ),
            CaptureCoordinateMapper.pixelPoint(
                fromLocalAppKitPoint: CapturePoint(x: end.x, y: end.y),
                geometry: geometry
            ),
            selectionRect
        )
    }

    private func updateLayers(_ changes: () -> Void = {}) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        frameLayer.frame = bounds
        dimLayer.frame = bounds
        borderLayer.frame = bounds
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.48).cgColor
        let dimmed = CGMutablePath()
        dimmed.addRect(bounds)
        if let selectionRect {
            dimmed.addRect(selectionRect)
            borderLayer.path = CGPath(
                rect: selectionRect.insetBy(dx: 0.5, dy: 0.5),
                transform: nil
            )
            effectiveAppearance.performAsCurrentDrawingAppearance {
                borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
            }
        } else {
            borderLayer.path = nil
        }
        dimLayer.path = dimmed
        CATransaction.commit()
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
