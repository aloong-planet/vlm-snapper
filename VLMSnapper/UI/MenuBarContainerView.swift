import SwiftUI
import VLMSnapperCore

enum MenuCaptureActionHandler {
    static func perform(
        route: MenuCaptureRoute,
        showProviderConfiguration: () -> Void,
        showPermissionRecovery: () -> Void,
        captureAfterPanelDismissal: () -> Void
    ) {
        switch route {
        case .configureProvider:
            showProviderConfiguration()
        case .recoverPermission:
            showPermissionRecovery()
        case .capture:
            captureAfterPanelDismissal()
        }
    }
}

public struct MenuBarCallbacks {
    public let onCapture: () -> Void
    public let onPermissionPrimaryAction: () -> Void
    public let onSelectProvider: (ProviderID) -> Void
    public let onValidateProvider: () -> Void
    public let onRefreshModels: () -> Void
    public let onSelectModel: (String) -> Void
    public let onProviderDone: () -> Void
    public let onOpenRecent: (String) -> Void
    public let onNavigate: (ManagementCenterDestination) -> Void
    public let onCheckUpdates: () -> Void
    public let onDownloadUpdate: () -> Void
    public let onOpenUpdateInformation: (URL) -> Void

    public init(
        onCapture: @escaping () -> Void,
        onPermissionPrimaryAction: @escaping () -> Void,
        onSelectProvider: @escaping (ProviderID) -> Void,
        onValidateProvider: @escaping () -> Void,
        onRefreshModels: @escaping () -> Void,
        onSelectModel: @escaping (String) -> Void,
        onProviderDone: @escaping () -> Void,
        onOpenRecent: @escaping (String) -> Void,
        onNavigate: @escaping (ManagementCenterDestination) -> Void,
        onCheckUpdates: @escaping () -> Void,
        onDownloadUpdate: @escaping () -> Void = {},
        onOpenUpdateInformation: @escaping (URL) -> Void = { _ in }
    ) {
        self.onCapture = onCapture
        self.onPermissionPrimaryAction = onPermissionPrimaryAction
        self.onSelectProvider = onSelectProvider
        self.onValidateProvider = onValidateProvider
        self.onRefreshModels = onRefreshModels
        self.onSelectModel = onSelectModel
        self.onProviderDone = onProviderDone
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
    private let providerSnapshot: ProviderSetupSnapshot
    private let providerConfigurations: [ProviderID: ProviderConfiguration]
    private let updateState: UpdateLifecycleState
    private let captureShortcut: String
    @Binding private var apiKey: String
    @Binding private var pendingModelID: String?
    private let callbacks: MenuBarCallbacks
    @State private var activeSheet: MenuEntrySheet?
    @Environment(\.menuBarPanelDismissalCoordinator) private var panelDismissalCoordinator

    public init(
        recentItems: [MenuRecentItem],
        permission: ScreenCapturePermissionReadiness,
        provider: ProviderReadiness,
        providerSnapshot: ProviderSetupSnapshot,
        providerConfigurations: [ProviderID: ProviderConfiguration] = [:],
        updateState: UpdateLifecycleState = .idle,
        captureShortcut: String = "⌥⇧S",
        apiKey: Binding<String>,
        pendingModelID: Binding<String?>,
        callbacks: MenuBarCallbacks
    ) {
        self.recentItems = recentItems
        self.permission = permission
        self.provider = provider
        self.providerSnapshot = providerSnapshot
        self.providerConfigurations = providerConfigurations
        self.updateState = updateState
        self.captureShortcut = captureShortcut
        _apiKey = apiKey
        _pendingModelID = pendingModelID
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .permission:
                ScreenCapturePermissionRecoveryView(
                    state: permission,
                    onPrimaryAction: callbacks.onPermissionPrimaryAction,
                    onDismiss: { activeSheet = nil }
                )
            case .provider:
                ProviderSetupView(
                    snapshot: providerSnapshot,
                    configurations: providerConfigurations,
                    apiKey: $apiKey,
                    pendingModelID: $pendingModelID,
                    onSelectProvider: callbacks.onSelectProvider,
                    onValidate: callbacks.onValidateProvider,
                    onRefresh: callbacks.onRefreshModels,
                    onSelectModel: callbacks.onSelectModel,
                    onCancel: {
                        apiKey = ""
                        activeSheet = nil
                    },
                    onDone: {
                        apiKey = ""
                        callbacks.onProviderDone()
                        activeSheet = nil
                    }
                )
            }
        }
    }

    private func routeCapture() {
        MenuCaptureActionHandler.perform(
            route: MenuCaptureRouter.route(permission: permission, provider: provider),
            showProviderConfiguration: { activeSheet = .provider },
            showPermissionRecovery: { activeSheet = .permission },
            captureAfterPanelDismissal: {
                guard let panelDismissalCoordinator else {
                    callbacks.onCapture()
                    return
                }
                panelDismissalCoordinator.performAfterDismissing(callbacks.onCapture)
            }
        )
    }
}

private enum MenuEntrySheet: String, Identifiable {
    case permission
    case provider

    var id: String { rawValue }
}
