import SwiftUI
import VLMSnapperCore

enum MenuCaptureActionHandler {
    static func perform(
        route: MenuCaptureRoute,
        performCapture: () -> Void
    ) {
        switch route {
        case .configureProvider, .recoverPermission, .capture:
            performCapture()
        }
    }
}

public struct MenuBarCallbacks {
    public let onCapture: () -> Void
    public let onOpenRecent: (String) -> Void
    public let onNavigate: (ManagementCenterDestination) -> Void
    public let onCheckUpdates: () -> Void
    public let onDownloadUpdate: () -> Void
    public let onOpenUpdateInformation: (URL) -> Void

    public init(
        onCapture: @escaping () -> Void,
        onOpenRecent: @escaping (String) -> Void,
        onNavigate: @escaping (ManagementCenterDestination) -> Void,
        onCheckUpdates: @escaping () -> Void,
        onDownloadUpdate: @escaping () -> Void = {},
        onOpenUpdateInformation: @escaping (URL) -> Void = { _ in }
    ) {
        self.onCapture = onCapture
        self.onOpenRecent = onOpenRecent
        self.onNavigate = onNavigate
        self.onCheckUpdates = onCheckUpdates
        self.onDownloadUpdate = onDownloadUpdate
        self.onOpenUpdateInformation = onOpenUpdateInformation
    }
}

public struct MenuBarContainerView: View {
    private let recentItems: [MenuRecentItem]
    private let permission: ScreenCapturePermissionReadiness
    private let provider: ProviderReadiness
    private let updateState: UpdateLifecycleState
    private let captureShortcut: String
    private let callbacks: MenuBarCallbacks

    public init(
        recentItems: [MenuRecentItem],
        permission: ScreenCapturePermissionReadiness,
        provider: ProviderReadiness,
        updateState: UpdateLifecycleState = .idle,
        captureShortcut: String = "⌥⇧S",
        callbacks: MenuBarCallbacks
    ) {
        self.recentItems = recentItems
        self.permission = permission
        self.provider = provider
        self.updateState = updateState
        self.captureShortcut = captureShortcut
        self.callbacks = callbacks
    }

    public var body: some View {
        MenuBarPanelView(
            recentItems: recentItems,
            provider: provider,
            updateState: updateState,
            captureShortcut: captureShortcut,
            onCapture: routeCapture,
            onOpenRecent: callbacks.onOpenRecent,
            onNavigate: callbacks.onNavigate,
            onCheckUpdates: callbacks.onCheckUpdates,
            onDownloadUpdate: callbacks.onDownloadUpdate,
            onOpenUpdateInformation: callbacks.onOpenUpdateInformation
        )
    }

    private func routeCapture() {
        MenuCaptureActionHandler.perform(
            route: MenuCaptureRouter.route(permission: permission, provider: provider),
            performCapture: callbacks.onCapture
        )
    }
}
