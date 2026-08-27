import AppKit
import ServiceManagement
import VLMSnapperCore

public final class SMAppServiceLoginItemAdapter: LoginItemServicing, @unchecked Sendable {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public func status() async -> LoginItemState {
        await MainActor.run {
            switch service.status {
            case .enabled:
                .enabled
            case .notRegistered:
                .disabled
            case .requiresApproval:
                .requiresApproval
            case .notFound:
                .unavailable
            @unknown default:
                .unavailable
            }
        }
    }

    public func register() async throws {
        try await MainActor.run { try service.register() }
    }

    public func unregister() async throws {
        try await service.unregister()
    }

    public func openSystemSettings() async {
        await MainActor.run {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
            ) else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

public final class DistributedPrimaryInstanceMessaging: PrimaryInstanceMessaging, @unchecked Sendable {
    private let notificationCenter: DistributedNotificationCenter
    private let notificationName: Notification.Name
    private let bundleIdentifier: String?
    private let observerLock = NSLock()
    private var observer: NSObjectProtocol?

    public init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        notificationCenter: DistributedNotificationCenter = .default()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.notificationCenter = notificationCenter
        notificationName = Notification.Name(
            "com.vlmsnapper.activation.\(bundleIdentifier ?? "application")"
        )
    }

    deinit {
        observerLock.lock()
        let observer = observer
        observerLock.unlock()
        if let observer { notificationCenter.removeObserver(observer) }
    }

    public func beginObserving(
        _ handler: @escaping @Sendable () async -> Void
    ) async {
        observerLock.withLock {
            guard observer == nil else { return }
            observer = notificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { _ in
                Task { await handler() }
            }
        }
    }

    public func requestActivation() async {
        notificationCenter.postNotificationName(
            notificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        guard let bundleIdentifier else { return }
        _ = await MainActor.run {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
            .activate(options: [.activateAllWindows])
        }
    }
}
