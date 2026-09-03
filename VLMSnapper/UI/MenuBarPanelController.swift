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

struct MenuBarPanelPlacement: Equatable {
    let frame: CGRect
    let arrowCenterX: CGFloat

    static func resolve(
        anchorFrame: CGRect,
        screenFrame: CGRect,
        contentSize: CGSize
    ) -> MenuBarPanelPlacement {
        let minimumOriginX = screenFrame.minX + MenuBarPanelMetrics.screenEdgeInset
        let maximumOriginX = max(
            minimumOriginX,
            screenFrame.maxX - MenuBarPanelMetrics.screenEdgeInset - contentSize.width
        )
        let idealOriginX = anchorFrame.midX - (contentSize.width / 2)
        let originX = min(max(idealOriginX, minimumOriginX), maximumOriginX)
        let maximumArrowCenterX = contentSize.width - MenuBarPanelMetrics.arrowEdgeInset
        let arrowCenterX = min(
            max(anchorFrame.midX - originX, MenuBarPanelMetrics.arrowEdgeInset),
            maximumArrowCenterX
        )
        let panelTop = min(anchorFrame.minY, screenFrame.maxY)
        let originY = panelTop - contentSize.height

        return MenuBarPanelPlacement(
            frame: CGRect(
                origin: CGPoint(x: originX, y: originY),
                size: contentSize
            ),
            arrowCenterX: arrowCenterX
        )
    }
}

enum MenuBarPanelDismissalTarget: Equatable {
    case panel
    case statusItem
    case outside
}

enum MenuBarPanelDismissalAction: Equatable {
    case keepOpen
    case dismiss
}

enum MenuBarPanelDismissalRouter {
    static func route(target: MenuBarPanelDismissalTarget) -> MenuBarPanelDismissalAction {
        target == .outside ? .dismiss : .keepOpen
    }

    static func route(
        eventWindowNumber: Int,
        eventLocationInWindow: CGPoint,
        panelWindowNumber: Int,
        statusItemWindowNumber: Int?,
        statusItemFrame: CGRect?
    ) -> MenuBarPanelDismissalAction {
        if eventWindowNumber == panelWindowNumber {
            return route(target: .panel)
        }
        if eventWindowNumber == statusItemWindowNumber,
           statusItemFrame?.contains(eventLocationInWindow) == true {
            return route(target: .statusItem)
        }
        return route(target: .outside)
    }
}

struct MenuBarPanelArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct MenuBarPanelChrome<Content: View>: View {
    let arrowCenterX: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear
                MenuBarPanelArrow()
                    .fill(VLMSnapperTheme.window)
                    .overlay(MenuBarPanelArrow().stroke(VLMSnapperTheme.border, lineWidth: 1))
                    .frame(
                        width: MenuBarPanelMetrics.arrowSize.width,
                        height: MenuBarPanelMetrics.arrowSize.height
                    )
                    .offset(x: arrowCenterX - (MenuBarPanelMetrics.arrowSize.width / 2))
            }
            .frame(width: MenuBarPanelMetrics.width, height: MenuBarPanelMetrics.arrowSize.height)

            content()
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MenuBarPanelMetrics.outerCornerRadius,
                        style: .continuous
                    )
                    .stroke(VLMSnapperTheme.border, lineWidth: 1)
                )
        }
        .frame(width: MenuBarPanelMetrics.width)
    }
}

private final class MenuBarPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class MenuBarPanelController<Content: View>: NSObject {
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanelWindow
    private let updateIndicator = NSView()
    private let onQuit: () -> Void
    private var hostingController: NSHostingController<AnyView>!
    private var currentContent: Content
    private var currentArrowCenterX = MenuBarPanelMetrics.width / 2
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
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
        panel = MenuBarPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        currentContent = content
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

        panel.animationBehavior = .none
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.becomesKeyOnlyIfNeeded = true

        let hostingController = NSHostingController(
            rootView: hostedContent(content, arrowCenterX: currentArrowCenterX)
        )
        self.hostingController = hostingController
        panel.contentViewController = hostingController
        resizePanelToFitContent()
    }

    public func update(content: Content) {
        currentContent = content
        hostingController.rootView = hostedContent(content, arrowCenterX: currentArrowCenterX)
        resizePanelToFitContent()
        if panel.isVisible {
            positionPanel()
        }
    }

    public func setUpdateIndicatorVisible(_ visible: Bool) {
        updateIndicator.isHidden = !visible
    }

    public func updateIndicator(for state: UpdateLifecycleState) {
        setUpdateIndicatorVisible(state.showsAttentionIndicator)
    }

    public func show() {
        guard !panel.isVisible, positionPanel() else { return }
        panel.orderFrontRegardless()
        installMouseMonitors()
    }

    public func hideForCapture() {
        hide()
    }

    @objc private func handleStatusItemAction() {
        switch MenuBarStatusItemInteractionRouter.route(eventType: NSApp.currentEvent?.type) {
        case .primaryPanel:
            togglePanel()
        case .contextMenu:
            guard let event = NSApp.currentEvent, let button = statusItem.button else { return }
            NSMenu.popUpContextMenu(contextMenu, with: event, for: button)
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            hide()
            return
        }
        show()
    }

    private func hide() {
        panel.orderOut(nil)
        removeMouseMonitors()
    }

    @discardableResult
    private func positionPanel() -> Bool {
        guard let button = statusItem.button,
              let window = button.window else {
            return false
        }
        resizePanelToFitContent()
        let anchorFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(anchorFrame.center) })
            ?? NSScreen.main
        guard let screen else { return false }
        let placement = MenuBarPanelPlacement.resolve(
            anchorFrame: anchorFrame,
            screenFrame: screen.visibleFrame,
            contentSize: panel.frame.size
        )
        currentArrowCenterX = placement.arrowCenterX
        hostingController.rootView = hostedContent(
            currentContent,
            arrowCenterX: placement.arrowCenterX
        )
        panel.setFrame(placement.frame, display: panel.isVisible)
        return true
    }

    private func resizePanelToFitContent() {
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        panel.setContentSize(
            CGSize(
                width: MenuBarPanelMetrics.width,
                height: ceil(max(fittingSize.height, MenuBarPanelMetrics.arrowSize.height))
            )
        )
    }

    private func installMouseMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) {
            [weak self] event in
            guard let self else { return event }
            let button = self.statusItem.button
            let action = MenuBarPanelDismissalRouter.route(
                eventWindowNumber: event.windowNumber,
                eventLocationInWindow: event.locationInWindow,
                panelWindowNumber: self.panel.windowNumber,
                statusItemWindowNumber: button?.window?.windowNumber,
                statusItemFrame: button.map { $0.convert($0.bounds, to: nil) }
            )
            if action == .dismiss {
                self.hide()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) {
            [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    private func removeMouseMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    @objc private func quitApplication() {
        onQuit()
    }

    private func hostedContent(_ content: Content, arrowCenterX: CGFloat) -> AnyView {
        AnyView(
            MenuBarPanelChrome(arrowCenterX: arrowCenterX) {
                content
            }
        )
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
