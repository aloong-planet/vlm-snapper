import AppKit
import SwiftUI
import VLMSnapperCore

enum MenuBarStatusItemInteraction: Equatable {
    case primaryPanel
    case contextMenu
}

enum MenuBarStatusItemInteractionRouter {
    static func route(eventType: NSEvent.EventType?) -> MenuBarStatusItemInteraction {
        eventType == .rightMouseUp ? .contextMenu : .primaryPanel
    }
}

@MainActor
public final class MenuBarPanelController<Content: View>: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let updateIndicator = NSView()
    private let onQuit: () -> Void
    private var hostingController: NSHostingController<AnyView>!
    lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: VLMSnapperStrings.menuQuit,
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }()

    public init(content: Content, onQuit: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onQuit = onQuit
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: VLMSnapperIcon.capture.rawValue,
            accessibilityDescription: VLMSnapperStrings.menuCapture
        )
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemAction)
        if let button = statusItem.button {
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        let hostingController = NSHostingController(rootView: hostedContent(content))
        self.hostingController = hostingController
        popover.contentViewController = hostingController
    }

    public func update(content: Content) {
        hostingController.rootView = hostedContent(content)
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

    public func hideForCapture() {
        popover.performClose(nil)
    }

    @objc private func handleStatusItemAction() {
        switch MenuBarStatusItemInteractionRouter.route(eventType: NSApp.currentEvent?.type) {
        case .primaryPanel:
            togglePopover()
        case .contextMenu:
            guard let event = NSApp.currentEvent, let button = statusItem.button else { return }
            NSMenu.popUpContextMenu(contextMenu, with: event, for: button)
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        show()
    }

    @objc private func quitApplication() {
        onQuit()
    }

    private func hostedContent(_ content: Content) -> AnyView {
        AnyView(content)
    }
}
