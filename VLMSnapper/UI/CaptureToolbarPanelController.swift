import AppKit
import SwiftUI

enum CaptureToolbarPlacement {
    static func origin(
        selectionFrame: CGRect,
        toolbarSize: CGSize,
        visibleScreenFrame: CGRect
    ) -> CGPoint {
        let gap = VLMSnapperUIConstants.toolbarSelectionGap
        let belowY = selectionFrame.minY - gap - toolbarSize.height
        let aboveY = selectionFrame.maxY + gap
        guard belowY >= visibleScreenFrame.minY
            || aboveY + toolbarSize.height <= visibleScreenFrame.maxY else {
            // No room below or above, as for a whole display: inside the selection's bottom-right corner.
            let x = min(selectionFrame.maxX, visibleScreenFrame.maxX) - gap - toolbarSize.width
            let y = max(selectionFrame.minY, visibleScreenFrame.minY) + gap
            return CGPoint(
                x: max(x, visibleScreenFrame.minX),
                y: min(y, visibleScreenFrame.maxY - toolbarSize.height)
            )
        }
        let rightmostVisibleX = max(
            visibleScreenFrame.minX,
            visibleScreenFrame.maxX - toolbarSize.width
        )
        let x = min(
            max(selectionFrame.minX, visibleScreenFrame.minX),
            rightmostVisibleX
        )
        return CGPoint(x: x, y: belowY >= visibleScreenFrame.minY ? belowY : aboveY)
    }
}

@MainActor
public final class CaptureToolbarPanelController {
    public let panel: NSPanel
    private var isSuspended = false

    public init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(
            rawValue: NSWindow.Level.screenSaver.rawValue + 1
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    public func show<Content: View>(
        content: Content,
        below selectionFrame: CGRect,
        on screen: NSScreen
    ) {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame.size = hostingView.fittingSize
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        panel.setFrameOrigin(
            CaptureToolbarPlacement.origin(
                selectionFrame: selectionFrame,
                toolbarSize: hostingView.fittingSize,
                visibleScreenFrame: screen.visibleFrame
            )
        )
        panel.orderFrontRegardless()
    }

    /// Moves the visible toolbar to follow a selection being adjusted, without rebuilding it.
    public func reposition(below selectionFrame: CGRect, on screen: NSScreen) {
        guard panel.isVisible else { return }
        panel.setFrameOrigin(
            CaptureToolbarPlacement.origin(
                selectionFrame: selectionFrame,
                toolbarSize: panel.frame.size,
                visibleScreenFrame: screen.visibleFrame
            )
        )
    }

    /// Hides a visible toolbar but keeps it for `resume`, while a new capture may still fail.
    public func suspend() {
        guard panel.isVisible else { return }
        isSuspended = true
        panel.orderOut(nil)
    }

    /// Shows a suspended toolbar again; does nothing after `hide()`.
    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        panel.orderFrontRegardless()
    }

    public func hide() {
        isSuspended = false
        panel.orderOut(nil)
        panel.contentView = nil
    }
}
