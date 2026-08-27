public protocol ScreenCapturePermissionAuthorizing: Sendable {
    func preflightScreenCaptureAccess() async -> Bool
    func requestScreenCaptureAuthorization() async -> Bool
}

public protocol PermissionRequestHistoryStoring: Sendable {
    func hasRequestedPermission() async throws -> Bool
    func markPermissionRequested() async throws
}

public enum ScreenCapturePermissionActionDisposition: Equatable, Sendable {
    case state(ScreenCapturePermissionReadiness)
    case openSystemSettings
    case restartApplication
    case noAction
}

public actor ScreenCapturePermissionCoordinator {
    private let authorizer: any ScreenCapturePermissionAuthorizing
    private let requestHistory: any PermissionRequestHistoryStoring
    private var restartRequired = false
    private var primaryActionInProgress = false

    public init(
        authorizer: any ScreenCapturePermissionAuthorizing,
        requestHistory: any PermissionRequestHistoryStoring
    ) {
        self.authorizer = authorizer
        self.requestHistory = requestHistory
    }

    public func refreshStatus() async throws -> ScreenCapturePermissionReadiness {
        if restartRequired {
            return .restartRequired
        }
        if await authorizer.preflightScreenCaptureAccess() {
            return .ready
        }
        return try await requestHistory.hasRequestedPermission()
            ? .unavailable
            : .notRequested
    }

    public func performPrimaryAction() async throws -> ScreenCapturePermissionActionDisposition {
        guard !primaryActionInProgress else {
            return .noAction
        }
        primaryActionInProgress = true
        defer { primaryActionInProgress = false }
        switch try await refreshStatus() {
        case .notRequested:
            try await requestHistory.markPermissionRequested()
            if await authorizer.requestScreenCaptureAuthorization() {
                restartRequired = true
                return .state(.restartRequired)
            }
            return .state(.unavailable)
        case .unavailable:
            return .openSystemSettings
        case .restartRequired:
            return .restartApplication
        case .ready:
            return .noAction
        }
    }
}
