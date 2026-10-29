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
    private let pointerLocation: @MainActor () -> CGPoint

    /// Displays covered by the current frozen overlay; a pending overlay does
    /// not change this until it is committed.
    public var presentedDisplayIDs: Set<UInt32> {
        Set(panels.map(\.displayID))
    }

    /// `pointerLocation` reads the pointer in global AppKit coordinates; the overlay opens with
    /// the snap region under it before the pointer moves.
    public init(pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }) {
        self.pointerLocation = pointerLocation
    }

    /// Covers every connected display before frozen frames exist. The current
    /// overlay is hidden but kept until `commit` retires it or `rollback`
    /// shows it again.
    @discardableResult
    public func presentPending(
        onSelection: @escaping @MainActor (Selection) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onSelectionChanging: @escaping @MainActor (CGRect?, NSScreen) -> Void = { _, _ in }
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
                onCancel: onCancel,
                onSelectionChanging: { [weak panel] localFrame in
                    guard let panel else { return }
                    onSelectionChanging(
                        localFrame.map {
                            $0.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
                        },
                        panel.overlayScreen
                    )
                }
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

    /// Gives the newest overlay its snap regions: the pending one while frames are freezing,
    /// otherwise the current one. An overlay a rollback may restore keeps the list taken with its
    /// own frozen frame. `nil` means the window list could not be read, so a click selects nothing
    /// while dragging still works.
    public func attachSnapRegions(_ resolver: CaptureSnapRegionResolver?) {
        let pointer = pointerLocation()
        for panel in pendingPanels.isEmpty ? panels : pendingPanels {
            guard let resolver else {
                panel.overlayView?.attachSnapRegions(nil, pointer: nil)
                continue
            }
            panel.overlayView?.attachSnapRegions(
                { [weak panel] point in panel?.snapRegion(at: point, resolver: resolver) ?? .zero },
                pointer: panel.localPoint(fromGlobal: pointer)
            )
        }
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
        acceptsMouseMovedEvents = true
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

    /// The snap region under a point of this panel's view, both in view coordinates. The
    /// resolver works in global top-left coordinates, flipped against the primary display.
    func snapRegion(at point: CGPoint, resolver: CaptureSnapRegionResolver) -> CGRect {
        let flipHeight = NSScreen.screens.first?.frame.height ?? frame.height
        func topLeft(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: flipHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        let display = CaptureSnapDisplay(
            frame: topLeft(overlayScreen.frame),
            visibleFrame: topLeft(overlayScreen.visibleFrame),
            pointPixelScale: Double(overlayScreen.backingScaleFactor)
        )
        let global = CGPoint(x: frame.minX + point.x, y: flipHeight - (frame.minY + point.y))
        let region = resolver.region(at: global, on: display)
        return CGRect(
            x: region.minX - frame.minX,
            y: flipHeight - region.maxY - frame.minY,
            width: region.width,
            height: region.height
        )
    }

    func localPoint(fromGlobal point: CGPoint) -> CGPoint? {
        guard frame.contains(point) else { return nil }
        return CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
    }
}

/// Renders with layers: the frozen frame is a layer's contents, so dragging only
/// rebuilds two small paths instead of redrawing a full-resolution frame.
private final class CaptureOverlayView: NSView {
    /// A press that moves this far or less is a click on the snap region (v1-core::REQ-006/AC-07).
    private static let dragThreshold: CGFloat = 3

    private enum SnapRegions {
        case awaiting
        case ready((CGPoint) -> CGRect)
        case unavailable
    }

    private let onSelection: @MainActor (CapturePoint, CapturePoint, CGRect) -> Void
    private let onCancel: @MainActor () -> Void
    /// The confirmed selection while it is adjusted, or `nil` when a press outside discards it.
    private let onSelectionChanging: @MainActor (CGRect?) -> Void
    private let frameLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    /// A resize or move of the confirmed selection in progress (v1-core::REQ-007).
    private var adjustment: (edges: Set<Edge>?, start: CGPoint, original: CGRect)?

    /// The sides a handle moves; `nil` edges in `adjustment` means a move.
    private enum Edge { case left, right, top, bottom }
    private static let handleSize: CGFloat = 7
    private static let handleHitSize: CGFloat = 12
    private var geometry: CaptureDisplayGeometry?
    private var snapRegions = SnapRegions.awaiting
    private var press: CGPoint?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    /// The snap region shown while no drag is in progress, or the region a click selected.
    private var snapped: CGRect?
    /// A click made before the window list arrived; resolved when it does.
    private var clickBeforeSnapRegions: CGPoint?
    /// A selection completed before the frozen frame arrived; finished by `attach`.
    private var completedBeforeFrame: CGRect?
    private var selectionSettled = false

    init(
        onSelection: @escaping @MainActor (CapturePoint, CapturePoint, CGRect) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onSelectionChanging: @escaping @MainActor (CGRect?) -> Void
    ) {
        self.onSelection = onSelection
        self.onCancel = onCancel
        self.onSelectionChanging = onSelectionChanging
        super.init(frame: .zero)
        wantsLayer = true
        frameLayer.contentsGravity = .resize
        frameLayer.magnificationFilter = .nearest
        frameLayer.minificationFilter = .nearest
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1
        handleLayer.lineWidth = 1
        for sublayer in [frameLayer, dimLayer, borderLayer, handleLayer] {
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
        if let selection = completedBeforeFrame {
            completedBeforeFrame = nil
            finishSelection(selection)
        }
    }

    /// `pointer` is where the pointer is in this view, or `nil` when it is on another display.
    func attachSnapRegions(_ region: ((CGPoint) -> CGRect)?, pointer: CGPoint?) {
        guard let region else {
            snapRegions = .unavailable
            if let click = clickBeforeSnapRegions {
                clickBeforeSnapRegions = nil
                complete(CGRect(origin: click, size: .zero))
            }
            return
        }
        snapRegions = .ready(region)
        if let click = clickBeforeSnapRegions {
            clickBeforeSnapRegions = nil
            let selection = region(click)
            snapped = selection
            complete(selection)
        } else if press == nil, !selectionSettled {
            snapped = pointer.map(region)
            updateLayers()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // Mouse movement reaches every display's overlay, not only the key one.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayers()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 1
        updateLayers {
            for sublayer in [frameLayer, dimLayer, borderLayer, handleLayer] {
                sublayer.contentsScale = scale
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayers()
    }

    override func mouseMoved(with event: NSEvent) {
        guard press == nil, !selectionSettled, case .ready(let region) = snapRegions else { return }
        snapped = region(convert(event.locationInWindow, from: nil))
        updateLayers()
    }

    override func mouseExited(with event: NSEvent) {
        guard press == nil, !selectionSettled, snapped != nil else { return }
        snapped = nil
        updateLayers()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        if let confirmed = confirmedSelection {
            if let edges = Self.handles(of: confirmed).first(where: { $0.hitRect.contains(point) })?.edges {
                adjustment = (edges, point, confirmed)
                return
            }
            if confirmed.contains(point) {
                adjustment = (nil, point, confirmed)
                return
            }
            // A press outside starts a new selection; the old one and its toolbar go away.
            onSelectionChanging(nil)
        }
        press = point
        dragStart = nil
        dragCurrent = nil
        completedBeforeFrame = nil
        clickBeforeSnapRegions = nil
        selectionSettled = false
        if case .ready(let region) = snapRegions { snapped = region(point) }
        updateLayers()
    }

    override func mouseDragged(with event: NSEvent) {
        if let adjustment {
            snapped = adjusted(adjustment, to: convert(event.locationInWindow, from: nil))
            updateLayers()
            onSelectionChanging(snapped)
            return
        }
        guard let press else { return }
        let point = convert(event.locationInWindow, from: nil)
        if dragStart == nil {
            guard hypot(point.x - press.x, point.y - press.y) > Self.dragThreshold else { return }
            dragStart = press
        }
        dragCurrent = point
        updateLayers()
    }

    override func mouseUp(with event: NSEvent) {
        if let adjustment {
            self.adjustment = nil
            let rect = adjusted(adjustment, to: convert(event.locationInWindow, from: nil))
            guard coversTwoPixels(rect) else {
                // Under two physical pixels: back to the selection before the adjustment.
                snapped = adjustment.original
                updateLayers()
                onSelectionChanging(adjustment.original)
                return
            }
            snapped = rect
            complete(rect)
            return
        }
        guard let press else { return }
        self.press = nil
        let end = convert(event.locationInWindow, from: nil)
        // A release far from the press is a drag even when no drag event arrived in between.
        if dragStart == nil, hypot(end.x - press.x, end.y - press.y) > Self.dragThreshold {
            dragStart = press
        }
        if dragStart != nil {
            dragCurrent = end
            if let rect = selectionRect { complete(rect) }
            return
        }
        switch snapRegions {
        case .ready(let region):
            let selection = region(press)
            snapped = selection
            complete(selection)
        case .awaiting:
            clickBeforeSnapRegions = press
        case .unavailable:
            // Without snap regions a click is an empty selection, as before snapping existed.
            complete(CGRect(origin: press, size: .zero))
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    private func complete(_ selection: CGRect) {
        selectionSettled = true
        // The confirmed selection is kept as one rectangle so it can be adjusted.
        dragStart = nil
        dragCurrent = nil
        snapped = selection
        updateLayers()
        guard geometry != nil else {
            completedBeforeFrame = selection
            return
        }
        finishSelection(selection)
    }

    private func finishSelection(_ selection: CGRect) {
        guard let geometry else { return }
        onSelection(
            CaptureCoordinateMapper.pixelPoint(
                fromLocalAppKitPoint: CapturePoint(x: selection.minX, y: selection.minY),
                geometry: geometry
            ),
            CaptureCoordinateMapper.pixelPoint(
                fromLocalAppKitPoint: CapturePoint(x: selection.maxX, y: selection.maxY),
                geometry: geometry
            ),
            selection
        )
    }

    /// The selection the toolbar belongs to, once the frozen frame is shown.
    private var confirmedSelection: CGRect? {
        guard selectionSettled, geometry != nil, press == nil,
              let snapped, !snapped.isEmpty else { return nil }
        return snapped
    }

    private func adjusted(
        _ adjustment: (edges: Set<Edge>?, start: CGPoint, original: CGRect),
        to point: CGPoint
    ) -> CGRect {
        let dx = point.x - adjustment.start.x
        let dy = point.y - adjustment.start.y
        let original = adjustment.original
        guard let edges = adjustment.edges else {
            return CGRect(
                x: min(max(original.minX + dx, bounds.minX), bounds.maxX - original.width),
                y: min(max(original.minY + dy, bounds.minY), bounds.maxY - original.height),
                width: original.width,
                height: original.height
            )
        }
        var minX = original.minX, maxX = original.maxX
        var minY = original.minY, maxY = original.maxY
        if edges.contains(.left) { minX += dx }
        if edges.contains(.right) { maxX += dx }
        if edges.contains(.bottom) { minY += dy }
        if edges.contains(.top) { maxY += dy }
        // Dragging past the opposite side flips the rectangle instead of inverting it.
        let left = max(min(minX, maxX), bounds.minX), right = min(max(minX, maxX), bounds.maxX)
        let bottom = max(min(minY, maxY), bounds.minY), top = min(max(minY, maxY), bounds.maxY)
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    private func coversTwoPixels(_ rect: CGRect) -> Bool {
        guard let geometry, geometry.logicalWidth > 0, geometry.logicalHeight > 0 else { return false }
        let scaleX = Double(geometry.pixelWidth) / geometry.logicalWidth
        let scaleY = Double(geometry.pixelHeight) / geometry.logicalHeight
        return Double(rect.width) * scaleX >= 2 && Double(rect.height) * scaleY >= 2
    }

    private static func handles(of rect: CGRect) -> [(center: CGPoint, edges: Set<Edge>, hitRect: CGRect)] {
        let points: [(CGPoint, Set<Edge>)] = [
            (CGPoint(x: rect.minX, y: rect.maxY), [.left, .top]),
            (CGPoint(x: rect.midX, y: rect.maxY), [.top]),
            (CGPoint(x: rect.maxX, y: rect.maxY), [.right, .top]),
            (CGPoint(x: rect.maxX, y: rect.midY), [.right]),
            (CGPoint(x: rect.maxX, y: rect.minY), [.right, .bottom]),
            (CGPoint(x: rect.midX, y: rect.minY), [.bottom]),
            (CGPoint(x: rect.minX, y: rect.minY), [.left, .bottom]),
            (CGPoint(x: rect.minX, y: rect.midY), [.left]),
        ]
        return points.map { center, edges in
            let hit = CGRect(x: center.x - handleHitSize / 2, y: center.y - handleHitSize / 2,
                             width: handleHitSize, height: handleHitSize)
            return (center, edges, hit)
        }
    }

    override func resetCursorRects() {
        guard let confirmed = confirmedSelection else { return }
        addCursorRect(confirmed, cursor: .openHand)
        for handle in Self.handles(of: confirmed) {
            addCursorRect(handle.hitRect, cursor: Self.cursor(for: handle.edges))
        }
    }

    private static func cursor(for edges: Set<Edge>) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch (edges.contains(.left), edges.contains(.right), edges.contains(.top), edges.contains(.bottom)) {
            case (true, _, true, _): position = .topLeft
            case (_, true, true, _): position = .topRight
            case (true, _, _, true): position = .bottomLeft
            case (_, true, _, true): position = .bottomRight
            case (true, _, _, _): position = .left
            case (_, true, _, _): position = .right
            case (_, _, true, _): position = .top
            default: position = .bottom
            }
            return .frameResize(position: position, directions: .all)
        }
        if edges == [.left] || edges == [.right] { return .resizeLeftRight }
        if edges == [.top] || edges == [.bottom] { return .resizeUpDown }
        return .crosshair
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
                handleLayer.strokeColor = NSColor.controlAccentColor.cgColor
                handleLayer.fillColor = NSColor.white.cgColor
            }
        } else {
            borderLayer.path = nil
        }
        if let confirmed = confirmedSelection {
            let handles = CGMutablePath()
            for handle in Self.handles(of: confirmed) {
                handles.addRect(CGRect(
                    x: handle.center.x - Self.handleSize / 2,
                    y: handle.center.y - Self.handleSize / 2,
                    width: Self.handleSize,
                    height: Self.handleSize
                ))
            }
            handleLayer.path = handles
        } else {
            handleLayer.path = nil
        }
        handleLayer.frame = bounds
        window?.invalidateCursorRects(for: self)
        dimLayer.path = dimmed
        CATransaction.commit()
    }

    /// The dragged rectangle while dragging; otherwise the snap region.
    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return snapped }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }
}
