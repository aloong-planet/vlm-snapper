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
final class MenuBarPanelDismissalCoordinator {
    private let isPanelShown: () -> Bool
    private let requestClose: () -> Void
    private var pendingAction: (() -> Void)?

    init(
        isPanelShown: @escaping () -> Bool,
        requestClose: @escaping () -> Void
    ) {
        self.isPanelShown = isPanelShown
        self.requestClose = requestClose
    }

    func performAfterDismissing(_ action: @escaping () -> Void) {
        guard isPanelShown() else {
            action()
            return
        }
        pendingAction = action
        requestClose()
    }

    func panelDidClose() {
        let action = pendingAction
        pendingAction = nil
        guard let action else { return }
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}

private struct MenuBarPanelDismissalCoordinatorKey: EnvironmentKey {
    static let defaultValue: MenuBarPanelDismissalCoordinator? = nil
}

extension EnvironmentValues {
    var menuBarPanelDismissalCoordinator: MenuBarPanelDismissalCoordinator? {
        get { self[MenuBarPanelDismissalCoordinatorKey.self] }
        set { self[MenuBarPanelDismissalCoordinatorKey.self] = newValue }
    }
}

@MainActor
public final class MenuBarPanelController<Content: View>: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let updateIndicator = NSView()
    private let onQuit: () -> Void
    private var hostingController: NSHostingController<AnyView>!
    private var dismissalCoordinator: MenuBarPanelDismissalCoordinator!
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
        dismissalCoordinator = MenuBarPanelDismissalCoordinator(
            isPanelShown: { [popover] in popover.isShown },
            requestClose: { [popover] in popover.performClose(nil) }
        )
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
        popover.delegate = self
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

    public func popoverDidClose(_ notification: Notification) {
        dismissalCoordinator.panelDidClose()
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
        return AnyView(
            content.environment(
                \.menuBarPanelDismissalCoordinator,
                dismissalCoordinator
            )
        )
    }
}
