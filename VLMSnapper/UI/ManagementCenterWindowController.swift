import AppKit
import SwiftUI
import VLMSnapperCore

@MainActor
public final class ManagementCenterWindowController: NSWindowController, NSWindowDelegate {
    private var records: [HistoryRecord]
    private var selectedRecordID: UUID?
    private var selectedImage: NSImage?
    private var selectedImageLoadFailed: Bool
    private var cleanupFailureCount: Int
    private var retention: HistoryRetentionPeriod
    private var settings: GeneralSettingsSnapshot
    private var providerSettings: ProviderSettingsConfiguration?
    private let callbacks: ManagementCenterCallbacks
    private let onClose: () -> Void
    private var currentDestination: ManagementCenterDestination = .history
    private var hostingController: NSHostingController<AnyView>?
    private var sessionID = UUID()
    private var navigationRequestID = UUID()
    private var hasPresented = false

    public init(
        records: [HistoryRecord],
        selectedRecordID: UUID? = nil,
        selectedImage: NSImage? = nil,
        selectedImageLoadFailed: Bool = false,
        cleanupFailureCount: Int = 0,
        retention: HistoryRetentionPeriod = .thirtyDays,
        settings: GeneralSettingsSnapshot = GeneralSettingsSnapshot(),
        providerSettings: ProviderSettingsConfiguration? = nil,
        callbacks: ManagementCenterCallbacks = ManagementCenterCallbacks(),
        onClose: @escaping () -> Void = {}
    ) {
        self.records = records
        self.selectedRecordID = selectedRecordID
        self.selectedImage = selectedImage
        self.selectedImageLoadFailed = selectedImageLoadFailed
        self.cleanupFailureCount = cleanupFailureCount
        self.retention = retention
        self.settings = settings
        self.providerSettings = providerSettings
        self.callbacks = callbacks
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ManagementCenterMetrics.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VLMSnapper"
        window.contentMinSize = NSSize(width: 920, height: 620)
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public func windowWillClose(_ notification: Notification) {
        sessionID = UUID()
        providerSettings?.credentialEditor.close()
        onClose()
    }

    public func show(destination: ManagementCenterDestination) {
        if let providerSettings, !providerSettings.credentialEditor.isOpen {
            providerSettings.onSelectProvider(providerSettings.snapshot.selectedProvider)
        }
        currentDestination = destination
        navigationRequestID = UUID()
        render(destination: destination)
        showWindow(nil)
        if !hasPresented, let window {
            if let screen = window.screen ?? NSScreen.main {
                window.setFrame(screen.visibleFrame, display: true)
            } else {
                window.center()
            }
            hasPresented = true
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func performAfterHiding(
        _ action: @escaping @MainActor () -> Void
    ) {
        window?.orderOut(nil)
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }

    public func hideForCapture() {
        window?.orderOut(nil)
    }

    public func resumeAfterResult() {
        render(destination: currentDestination)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func render(destination: ManagementCenterDestination) {
        // Attaching a hosting controller can adopt the SwiftUI minimum size.
        // Keep the user's frame, including on subsequent content updates.
        let frame = window?.frame
        defer { if let frame { window?.setFrame(frame, display: false) } }
        let view = AnyView(ManagementCenterView(
            destination: destination,
            navigationRequestID: navigationRequestID,
            records: records,
            selectedRecordID: selectedRecordID,
            selectedImage: selectedImage,
            selectedImageLoadFailed: selectedImageLoadFailed,
            cleanupFailureCount: cleanupFailureCount,
            retention: retention,
            settings: settings,
            providerSettings: providerSettings,
            callbacks: callbacks
        ).id(sessionID))
        if let hostingController {
            hostingController.rootView = view
        } else {
            let controller = NSHostingController(rootView: view)
            hostingController = controller
            window?.contentViewController = controller
        }
    }

    public func update(
        records: [HistoryRecord],
        selectedRecordID: UUID?,
        selectedImage: NSImage?,
        selectedImageLoadFailed: Bool = false,
        cleanupFailureCount: Int,
        retention: HistoryRetentionPeriod,
        settings: GeneralSettingsSnapshot,
        providerSettings: ProviderSettingsConfiguration?
    ) {
        self.records = records
        self.selectedRecordID = selectedRecordID
        self.selectedImage = selectedImage
        self.selectedImageLoadFailed = selectedImageLoadFailed
        self.cleanupFailureCount = cleanupFailureCount
        self.retention = retention
        self.settings = settings
        self.providerSettings = providerSettings
        if window?.isVisible == true {
            render(destination: currentDestination)
        }
    }
}
