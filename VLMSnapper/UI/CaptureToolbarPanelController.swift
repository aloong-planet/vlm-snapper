import AppKit
import SwiftUI

enum CaptureToolbarPlacement {
    static func origin(
        selectionFrame: CGRect,
        toolbarSize: CGSize,
        visibleScreenFrame: CGRect
    ) -> CGPoint {
        let preferredBelowY = selectionFrame.minY
            - VLMSnapperUIConstants.toolbarSelectionGap
            - toolbarSize.height
        let y: CGFloat
        if preferredBelowY >= visibleScreenFrame.minY {
            y = preferredBelowY
        } else {
            y = min(
                selectionFrame.maxY + VLMSnapperUIConstants.toolbarSelectionGap,
                visibleScreenFrame.maxY - toolbarSize.height
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
        return CGPoint(x: x, y: y)
    }
}

@MainActor
public final class CaptureToolbarPanelController {
    public let panel: NSPanel

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

    public func hide() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}
