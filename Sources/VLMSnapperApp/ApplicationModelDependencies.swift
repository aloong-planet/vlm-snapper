import AppKit
import VLMSnapperCore
import VLMSnapperSparkle
import VLMSnapperUI

/// External effects required by the application model. Isolated callers must
/// supply every adapter; there is no partial override that falls back to live IO.
@MainActor
struct ApplicationModelDependencies {
    let credentialStore: any ProviderCredentialStoring
    let modelHTTP: any ProviderHTTPDataLoading
    let operationHTTP: any ProviderHTTPStreaming
    let screenshotRoot: URL
    let permissionAuthorizer: any ScreenCapturePermissionAuthorizing
    let permissionHistory: any PermissionRequestHistoryStoring
    let retentionPreferences: any RetentionPreferenceStoring
    let permissionChecker: any ScreenCapturePermissionChecking
    let frozenDisplayCapturer: any FrozenDisplayCapturing
    let displayMonitor: CaptureDisplayMonitor
    let loginService: any LoginItemServicing
    let makeUpdateDriver: (@escaping @Sendable (UpdateLifecycleEvent) async -> Void) -> any UpdateDriving
    let makeShortcutBackend: () throws -> any GlobalShortcutRegistrationBackend

    static func live() throws -> Self {
        let permission = CoreGraphicsScreenCapturePermissionChecker()
        return Self(
            credentialStore: AppleKeychainProviderCredentialStore(),
            modelHTTP: URLSessionProviderHTTPDataLoader(),
            operationHTTP: URLSessionProviderHTTPStreamer(),
            screenshotRoot: try ApplicationDirectories.screenshotRoot(),
            permissionAuthorizer: permission,
            permissionHistory: UserDefaultsPermissionRequestHistoryStore(),
            retentionPreferences: UserDefaultsRetentionPreferenceStore(),
            permissionChecker: permission,
            frozenDisplayCapturer: ScreenCaptureKitFrozenDisplayCapturer(),
            displayMonitor: CaptureDisplayMonitor(
                notifications: .default,
                workspaceNotifications: NSWorkspace.shared.notificationCenter,
                readGeometries: CaptureDisplayMonitor.liveGeometries
            ),
            loginService: SMAppServiceLoginItemAdapter(),
            makeUpdateDriver: { SparkleUpdateDriver(eventHandler: $0) },
            makeShortcutBackend: { try CarbonGlobalShortcutBackend() }
        )
    }
}
