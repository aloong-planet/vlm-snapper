import AppKit
import VLMSnapperCore

/// Reads display state at the OS boundary; notification payloads contain no geometry.
@MainActor
final class CaptureDisplayMonitor: NSObject {
    private let notifications: NotificationCenter
    private let workspaceNotifications: NotificationCenter
    private let readGeometries: @MainActor () -> [CaptureDisplayGeometry]
    private var onChange: (@MainActor ([CaptureDisplayGeometry]) -> Void)?

    init(
        notifications: NotificationCenter,
        workspaceNotifications: NotificationCenter,
        readGeometries: @escaping @MainActor () -> [CaptureDisplayGeometry]
    ) {
        self.notifications = notifications
        self.workspaceNotifications = workspaceNotifications
        self.readGeometries = readGeometries
        super.init()
    }

    func currentGeometries() -> [CaptureDisplayGeometry] { readGeometries() }

    func start(_ onChange: @escaping @MainActor ([CaptureDisplayGeometry]) -> Void) {
        stop()
        self.onChange = onChange
        notifications.addObserver(self, selector: #selector(configurationChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaysSlept),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
    }

    func stop() {
        notifications.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspaceNotifications.removeObserver(self, name: NSWorkspace.screensDidSleepNotification, object: nil)
        onChange = nil
    }

    @objc private func configurationChanged(_ notification: Notification) {
        onChange?(currentGeometries())
    }

    @objc private func displaysSlept(_ notification: Notification) {
        onChange?([])
    }

    static func liveGeometries() -> [CaptureDisplayGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value,
                  CGDisplayIsAsleep(id) == 0 else { return nil }
            return currentCaptureDisplayGeometry(for: id, pointPixelScale: Float(screen.backingScaleFactor))
        }
    }
}
