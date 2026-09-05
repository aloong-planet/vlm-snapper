import SwiftUI
import VLMSnapperCore

public struct OnboardingCallbacks {
    public let onPermissionPrimaryAction: () -> Void
    public let onOpenProviderSettings: () -> Void
    public let onStart: () -> Void
    public let onFinishLater: () -> Void

    public init(
        onPermissionPrimaryAction: @escaping () -> Void,
        onOpenProviderSettings: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onFinishLater: @escaping () -> Void
    ) {
        self.onPermissionPrimaryAction = onPermissionPrimaryAction
        self.onOpenProviderSettings = onOpenProviderSettings
        self.onStart = onStart
        self.onFinishLater = onFinishLater
    }
}

public struct OnboardingContainerView: View {
    private let snapshot: OnboardingSnapshot
    private let callbacks: OnboardingCallbacks
    @State private var activeSheet: ActiveSheet?

    public init(
        snapshot: OnboardingSnapshot,
        callbacks: OnboardingCallbacks
    ) {
        self.snapshot = snapshot
        self.callbacks = callbacks
    }

    public var body: some View {
        OnboardingView(
            snapshot: snapshot,
            onConfigurePermission: { activeSheet = .permission },
            onConfigureProvider: callbacks.onOpenProviderSettings,
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
            case .privacy:
                StoragePrivacyDetailView(onClose: { activeSheet = nil })
            }
        }
    }
}

private enum ActiveSheet: String, Identifiable {
    case permission
    case privacy

    var id: String { rawValue }
}
