import AppKit
import SwiftUI
import VLMSnapperCore

@MainActor
public final class MenuBarPanelController<Content: View>: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let updateIndicator = NSView()

    public init(content: Content) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: VLMSnapperIcon.capture.rawValue,
            accessibilityDescription: VLMSnapperStrings.menuCapture
        )
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        if let button = statusItem.button {
            updateIndicator.translatesAutoresizingMaskIntoConstraints = false
            updateIndicator.wantsLayer = true
            updateIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            updateIndicator.layer?.cornerRadius = 3
            updateIndicator.isHidden = true
            button.addSubview(updateIndicator)
            NSLayoutConstraint.activate([
                updateIndicator.widthAnchor.constraint(equalToConstant: 6),
                updateIndicator.heightAnchor.constraint(equalToConstant: 6),
                updateIndicator.topAnchor.constraint(equalTo: button.topAnchor, constant: 1),
                updateIndicator.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
            ])
        }
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

    public func setUpdateIndicatorVisible(_ visible: Bool) {
        updateIndicator.isHidden = !visible
    }

    public func updateIndicator(for state: UpdateLifecycleState) {
        setUpdateIndicatorVisible(state.showsAttentionIndicator)
    }

    public func show() {
        guard !popover.isShown, let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        show()
    }
}
