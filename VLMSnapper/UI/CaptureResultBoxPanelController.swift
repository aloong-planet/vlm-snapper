import AppKit
import SwiftUI

enum CaptureResultBoxPlacement {
    /// The box's default place: the right edge of the display's usable area (v1-core::REQ-010/AC-02).
    static func frame(visibleScreenFrame: CGRect) -> CGRect {
        let inset = CaptureResultBoxMetrics.edgeInset
        let width = CaptureResultBoxMetrics.width
        let height = min(visibleScreenFrame.height - 2 * inset, CaptureResultBoxMetrics.maximumHeight)
        return CGRect(
            x: visibleScreenFrame.maxX - inset - width,
            y: visibleScreenFrame.maxY - inset - height,
            width: width,
            height: height
        )
    }

    /// Where a drag may take the box: anywhere it stays on the display's usable area.
    static func clampedOrigin(_ origin: CGPoint, size: CGSize, visibleScreenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: max(visibleScreenFrame.minX, min(origin.x, visibleScreenFrame.maxX - size.width)),
            y: max(visibleScreenFrame.minY, min(origin.y, visibleScreenFrame.maxY - size.height))
        )
    }
}

final class CaptureResultBoxPanel: NSPanel {
    var onEscape: (@MainActor () -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // The same level as the toolbar, which is ordered in front of the box.
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // Selecting text and the keyboard need a key window; the panel still does not activate the application.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// `NSPanel` would close itself on Escape; here Escape leaves the capture (v1-core::REQ-012/AC-03).
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
public final class CaptureResultBoxPanelController {
    public let state = CaptureResultBoxState()
    private let panel = CaptureResultBoxPanel()
    private var visibleScreenFrame = CGRect.zero
    private var draggedOrigin: CGPoint?
    private var isSuspended = false

    public init(actions: CaptureResultBoxActions, onEscape: @escaping @MainActor () -> Void) {
        panel.onEscape = onEscape
        panel.contentView = NSHostingView(rootView: CaptureResultBoxView(
            state: state,
            actions: actions,
            onMove: { [weak self] origin in self?.move(to: origin) }
        ))
    }

    /// Where the box is, while it is on screen.
    public var frame: CGRect? {
        panel.isVisible ? panel.frame : nil
    }

    /// Shows the box on a display, where the user last dragged it during this capture if they did.
    public func show(on screen: NSScreen) {
        guard !isSuspended else { return }
        visibleScreenFrame = screen.visibleFrame
        var frame = CaptureResultBoxPlacement.frame(visibleScreenFrame: visibleScreenFrame)
        if let draggedOrigin {
            frame.origin = CaptureResultBoxPlacement.clampedOrigin(
                draggedOrigin,
                size: frame.size,
                visibleScreenFrame: visibleScreenFrame
            )
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    /// Hides a visible box but keeps it for `resume`, while a new capture may still fail.
    public func suspend() {
        guard panel.isVisible else { return }
        isSuspended = true
        panel.orderOut(nil)
    }

    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        panel.orderFrontRegardless()
    }

    /// Ends the capture this box belonged to: the next one starts at the default place.
    public func reset() {
        hide()
        isSuspended = false
        draggedOrigin = nil
        state.presentation = nil
    }

    private func move(to origin: CGPoint) {
        let clamped = CaptureResultBoxPlacement.clampedOrigin(
            origin,
            size: panel.frame.size,
            visibleScreenFrame: visibleScreenFrame
        )
        draggedOrigin = clamped
        panel.setFrameOrigin(clamped)
    }
}

/// Asks before an unsaved result is thrown away (v1-core::REQ-012/AC-04).
@MainActor
public enum UnsavedResultConfirmation {
    public static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = VLMSnapperStrings.discardUnsavedTitle
        alert.informativeText = VLMSnapperStrings.discardUnsavedBody
        alert.addButton(withTitle: VLMSnapperStrings.discardUnsavedAction)
        alert.addButton(withTitle: VLMSnapperStrings.cancel)
        return alert
    }

    public static func confirm() -> Bool {
        makeAlert().runModal() == .alertFirstButtonReturn
    }
}
