import AppKit
import SwiftUI

// Only an already-verified image snapshot crosses into the preview. It never
// reopens a file path that could have been replaced since history selection.
struct HistoryPreviewImage: Identifiable {
    let id = UUID()
    let image: NSImage
}

struct HistoryImagePreview: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss
    @State private var fitsWindow = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(VLMSnapperStrings.originalScreenshot).font(.headline)
                Spacer()
                Text(VLMSnapperStrings.historyZoomHint).foregroundStyle(VLMSnapperTheme.secondaryText)
                Button(fitsWindow ? VLMSnapperStrings.historyActualSize : VLMSnapperStrings.historyFitImage) {
                    fitsWindow.toggle()
                }
                .accessibilityIdentifier("history-image-size")
                Button(VLMSnapperStrings.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("history-image-close")
            }
            .padding(16)
            Divider()
            HistoryImageViewport(image: image, fitsWindow: $fitsWindow)
                .background(VLMSnapperTheme.subtleSurface)
        }
        .background(VLMSnapperTheme.surface)
        .frame(width: min(1000, (NSScreen.main?.visibleFrame.width ?? 1024) - 80),
               height: min(640, (NSScreen.main?.visibleFrame.height ?? 768) - 100))
        .background(PreviewBackdropDismissal(onDismiss: { dismiss() }))
    }
}

// Native sheets block their parent's controls but do not dismiss on backdrop clicks.
// Observe only this sheet's parent, and consume the entire click before dismissal.
private struct PreviewBackdropDismissal: NSViewRepresentable {
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> BackdropObserverView { BackdropObserverView() }
    func updateNSView(_ view: BackdropObserverView, context: Context) { view.onDismiss = onDismiss }
    static func dismantleNSView(_ view: BackdropObserverView, coordinator: ()) { view.stopObserving() }
}

private final class BackdropObserverView: NSView {
    var onDismiss: (() -> Void)?
    private var monitor: Any?
    private var clickStart: NSPoint?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event) == nil
            }
            return consumed ? nil : event
        }
    }

    func stopObserving() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        clickStart = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let sheet = window, let parent = sheet.sheetParent,
              parent.attachedSheet === sheet, sheet.isVisible else {
            clickStart = nil
            return event
        }
        let outside = event.window === parent
            && parent.contentLayoutRect.contains(event.locationInWindow)
            && !sheet.frame.contains(parent.convertPoint(toScreen: event.locationInWindow))
        if event.type == .leftMouseDown {
            clickStart = outside ? event.locationInWindow : nil
            return outside ? nil : event
        }
        guard let start = clickStart else { return event }
        clickStart = nil
        if outside, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) < 4 {
            onDismiss?()
        }
        return nil
    }
}

private struct HistoryImageViewport: NSViewRepresentable {
    let image: NSImage
    @Binding var fitsWindow: Bool

    func makeNSView(context: Context) -> ImageZoomScrollView { ImageZoomScrollView(image: image) }

    func updateNSView(_ view: ImageZoomScrollView, context: Context) {
        view.onManualZoom = { fitsWindow = false }
        if view.fitsWindow != fitsWindow { view.setFitMode(fitsWindow) }
    }
}

private final class ImageZoomScrollView: NSScrollView {
    var onManualZoom: (() -> Void)?
    private(set) var fitsWindow = true
    private var lastViewportSize = NSSize.zero

    init(image: NSImage) {
        super.init(frame: .zero)
        contentView = CenteredImageClipView()
        drawsBackground = false
        contentView.drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        scrollerStyle = .overlay
        autohidesScrollers = true
        minMagnification = 0.001
        maxMagnification = 8
        let size: NSSize
        if let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            size = image.size
        }
        let picture = PannableImageView(frame: NSRect(origin: .zero, size: size))
        picture.image = image
        picture.imageScaling = .scaleAxesIndependently
        picture.setAccessibilityLabel(VLMSnapperStrings.originalScreenshot)
        picture.setAccessibilityIdentifier("history-original-image")
        documentView = picture
    }

    required init?(coder: NSCoder) { nil }

    private var fitScale: CGFloat {
        guard let size = documentView?.frame.size else { return 1 }
        return min(1, max(1, contentSize.width - 40) / max(1, size.width),
                   max(1, contentSize.height - 40) / max(1, size.height))
    }

    override func layout() {
        super.layout()
        guard contentSize.width > 0, contentSize.height > 0, lastViewportSize != contentSize else { return }
        lastViewportSize = contentSize
        minMagnification = min(0.05, fitScale)
        if fitsWindow { setFitMode(true) }
    }

    func setFitMode(_ fits: Bool) {
        fitsWindow = fits
        minMagnification = min(0.05, fitScale)
        let center = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        setMagnification(fits ? fitScale : 1, centeredAt: center)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty, event.scrollingDeltaY != 0 else { return }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 16)
        let next = min(maxMagnification, max(minMagnification,
            magnification * exp(min(100, max(-100, delta)) * 0.002)))
        var location = event.locationInWindow
        if event.window == nil, let window { location = window.convertPoint(fromScreen: location) }
        let anchor = contentView.convert(location, from: nil)
        fitsWindow = false
        setMagnification(next, centeredAt: anchor)
        onManualZoom?()
    }
}

private final class CenteredImageClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        guard let frame = documentView?.frame else { return result }
        if result.width > frame.width { result.origin.x = frame.midX - result.width / 2 }
        if result.height > frame.height { result.origin.y = frame.midY - result.height / 2 }
        return result
    }
}

private final class PannableImageView: NSImageView {
    private var dragStart: (point: NSPoint, origin: NSPoint)?

    override func resetCursorRects() { addCursorRect(visibleRect, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        guard let scroll = enclosingScrollView else { return }
        dragStart = (event.locationInWindow, scroll.contentView.bounds.origin)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let scroll = enclosingScrollView else { return }
        let delta = NSPoint(x: (event.locationInWindow.x - start.point.x) / scroll.magnification,
                            y: (event.locationInWindow.y - start.point.y) / scroll.magnification)
        var bounds = scroll.contentView.bounds
        bounds.origin = NSPoint(x: start.origin.x - delta.x, y: start.origin.y - delta.y)
        scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        NSCursor.openHand.set()
    }
}
