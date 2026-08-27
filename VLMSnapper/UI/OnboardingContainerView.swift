import SwiftUI
import VLMSnapperCore

public struct OnboardingCallbacks {
    public let onPermissionPrimaryAction: () -> Void
    public let onSelectProvider: (ProviderID) -> Void
    public let onValidateProvider: () -> Void
    public let onRefreshModels: () -> Void
    public let onSelectModel: (String) -> Void
    public let onProviderDone: () -> Void
    public let onStart: () -> Void
    public let onFinishLater: () -> Void

    public init(
        onPermissionPrimaryAction: @escaping () -> Void,
        onSelectProvider: @escaping (ProviderID) -> Void,
        onValidateProvider: @escaping () -> Void,
        onRefreshModels: @escaping () -> Void,
        onSelectModel: @escaping (String) -> Void,
        onProviderDone: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onFinishLater: @escaping () -> Void
    ) {
        self.onPermissionPrimaryAction = onPermissionPrimaryAction
        self.onSelectProvider = onSelectProvider
        self.onValidateProvider = onValidateProvider
        self.onRefreshModels = onRefreshModels
        self.onSelectModel = onSelectModel
        self.onProviderDone = onProviderDone
        self.onStart = onStart
        self.onFinishLater = onFinishLater
    }
}

public struct OnboardingContainerView: View {
    private let snapshot: OnboardingSnapshot
    private let providerSnapshot: ProviderSetupSnapshot
    @Binding private var apiKey: String
    @Binding private var pendingModelID: String?
    private let callbacks: OnboardingCallbacks
    @State private var activeSheet: ActiveSheet?

    public init(
        snapshot: OnboardingSnapshot,
        providerSnapshot: ProviderSetupSnapshot,
        apiKey: Binding<String>,
        pendingModelID: Binding<String?>,
        callbacks: OnboardingCallbacks
    ) {
        self.snapshot = snapshot
        self.providerSnapshot = providerSnapshot
        _apiKey = apiKey
        _pendingModelID = pendingModelID
        self.callbacks = callbacks
    }

    public var body: some View {
        OnboardingView(
            snapshot: snapshot,
            onConfigurePermission: { activeSheet = .permission },
            onConfigureProvider: { activeSheet = .provider },
            onViewPrivacy: { activeSheet = .privacy },
            onStart: callbacks.onStart,
            onFinishLater: callbacks.onFinishLater
        )
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .permission:
                ScreenCapturePermissionRecoveryView(
                    state: snapshot.permission,
                    onPrimaryAction: callbacks.onPermissionPrimaryAction,
                    onDismiss: { activeSheet = nil }
                )
            case .provider:
                ProviderSetupView(
                    snapshot: providerSnapshot,
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
            case .privacy:
                StoragePrivacyDetailView(onClose: { activeSheet = nil })
            }
        }
    }
}

private enum ActiveSheet: String, Identifiable {
    case permission
    case provider
    case privacy

    var id: String { rawValue }
}
