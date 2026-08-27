public enum ScreenCapturePermissionReadiness: Equatable, Sendable {
    case notRequested
    case unavailable
    case restartRequired
    case ready
}

public enum ProviderReadiness: Equatable, Sendable {
    case missing
    case pendingModel(ProviderID)
    case ready(provider: ProviderID, modelID: String)
}

public enum OnboardingBlocker: Equatable, Sendable {
    case screenCapturePermission
    case providerModel
}

public struct OnboardingSnapshot: Equatable, Sendable {
    public let permission: ScreenCapturePermissionReadiness
    public let provider: ProviderReadiness
    public let blocker: OnboardingBlocker?
    public let canStart: Bool
    public let canFinishLater: Bool

    public init(
        permission: ScreenCapturePermissionReadiness,
        provider: ProviderReadiness,
        blocker: OnboardingBlocker?,
        canStart: Bool,
        canFinishLater: Bool
    ) {
        self.permission = permission
        self.provider = provider
        self.blocker = blocker
        self.canStart = canStart
        self.canFinishLater = canFinishLater
    }
}

public struct OnboardingSession: Equatable, Sendable {
    public var permission: ScreenCapturePermissionReadiness
    public var provider: ProviderReadiness

    public init(
        permission: ScreenCapturePermissionReadiness,
        provider: ProviderReadiness
    ) {
        self.permission = permission
        self.provider = provider
    }

    public var snapshot: OnboardingSnapshot {
        let blocker: OnboardingBlocker?
        if permission != .ready {
            blocker = .screenCapturePermission
        } else if case .ready = provider {
            blocker = nil
        } else {
            blocker = .providerModel
        }
        return OnboardingSnapshot(
            permission: permission,
            provider: provider,
            blocker: blocker,
            canStart: blocker == nil,
            canFinishLater: true
        )
    }
}

public enum MenuCaptureRoute: Equatable, Sendable {
    case configureProvider
    case recoverPermission
    case capture
}

public enum MenuCaptureRouter {
    public static func route(
        permission: ScreenCapturePermissionReadiness,
        provider: ProviderReadiness
    ) -> MenuCaptureRoute {
        guard case .ready = provider else {
            return .configureProvider
        }
        guard permission == .ready else {
            return .recoverPermission
        }
        return .capture
    }
}
