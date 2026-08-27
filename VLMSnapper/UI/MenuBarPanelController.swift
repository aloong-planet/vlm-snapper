import AppKit
import SwiftUI

@MainActor
public final class MenuBarPanelController<Content: View>: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    public init(content: Content) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: VLMSnapperIcon.capture.rawValue,
            accessibilityDescription: VLMSnapperStrings.menuCapture
        )
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: content)
    }

    public func update(content: Content) {
        guard let hostingController = popover.contentViewController
            as? NSHostingController<Content> else {
            return
        }
        hostingController.rootView = content
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else {
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
