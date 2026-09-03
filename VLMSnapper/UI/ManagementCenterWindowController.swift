import AppKit
import SwiftUI
import VLMSnapperCore

@MainActor
public final class ManagementCenterWindowController: NSWindowController {
    private var records: [HistoryRecord]
    private var selectedRecordID: UUID?
    private var selectedImage: NSImage?
    private var cleanupFailureCount: Int
    private var retention: HistoryRetentionPeriod
    private var settings: GeneralSettingsSnapshot
    private var providerSettings: ProviderSettingsConfiguration?
    private let callbacks: ManagementCenterCallbacks
    private var currentDestination: ManagementCenterDestination = .history
    private var hostingController: NSHostingController<ManagementCenterView>?

    public init(
        records: [HistoryRecord],
        selectedRecordID: UUID? = nil,
        selectedImage: NSImage? = nil,
        cleanupFailureCount: Int = 0,
        retention: HistoryRetentionPeriod = .thirtyDays,
        settings: GeneralSettingsSnapshot = GeneralSettingsSnapshot(),
        providerSettings: ProviderSettingsConfiguration? = nil,
        callbacks: ManagementCenterCallbacks = ManagementCenterCallbacks()
    ) {
        self.records = records
        self.selectedRecordID = selectedRecordID
        self.selectedImage = selectedImage
        self.cleanupFailureCount = cleanupFailureCount
        self.retention = retention
        self.settings = settings
        self.providerSettings = providerSettings
        self.callbacks = callbacks
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ManagementCenterMetrics.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VLMSnapper"
        window.contentMinSize = NSSize(width: 920, height: 620)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public func show(destination: ManagementCenterDestination) {
        currentDestination = destination
        render(destination: destination)
        showWindow(nil)
        window?.center()
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

    private func render(destination: ManagementCenterDestination) {
        let view = ManagementCenterView(
            destination: destination,
            records: records,
            selectedRecordID: selectedRecordID,
            selectedImage: selectedImage,
            cleanupFailureCount: cleanupFailureCount,
            retention: retention,
            settings: settings,
            providerSettings: providerSettings,
            callbacks: callbacks
        )
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
        cleanupFailureCount: Int,
        retention: HistoryRetentionPeriod,
        settings: GeneralSettingsSnapshot,
        providerSettings: ProviderSettingsConfiguration?
    ) {
        self.records = records
        self.selectedRecordID = selectedRecordID
        self.selectedImage = selectedImage
        self.cleanupFailureCount = cleanupFailureCount
        self.retention = retention
        self.settings = settings
        self.providerSettings = providerSettings
        if window?.isVisible == true {
            render(destination: currentDestination)
        }
    }
}
