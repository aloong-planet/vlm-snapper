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
    private let callbacks: ManagementCenterCallbacks
    private var currentDestination: ManagementCenterDestination = .history

    public init(
        records: [HistoryRecord],
        selectedRecordID: UUID? = nil,
        selectedImage: NSImage? = nil,
        cleanupFailureCount: Int = 0,
        retention: HistoryRetentionPeriod = .thirtyDays,
        callbacks: ManagementCenterCallbacks = ManagementCenterCallbacks()
    ) {
        self.records = records
        self.selectedRecordID = selectedRecordID
        self.selectedImage = selectedImage
        self.cleanupFailureCount = cleanupFailureCount
        self.retention = retention
        self.callbacks = callbacks
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VLMSnapper"
        window.minSize = NSSize(width: 920, height: 620)
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

    private func render(destination: ManagementCenterDestination) {
        window?.contentViewController = NSHostingController(
            rootView: ManagementCenterView(
                destination: destination,
                records: records,
                selectedRecordID: selectedRecordID,
                selectedImage: selectedImage,
                cleanupFailureCount: cleanupFailureCount,
                retention: retention,
                callbacks: callbacks
            )
        )
    }

    public func update(
        records: [HistoryRecord],
        selectedRecordID: UUID?,
        selectedImage: NSImage?,
        cleanupFailureCount: Int,
        retention: HistoryRetentionPeriod
    ) {
        self.records = records
        self.selectedRecordID = selectedRecordID
        self.selectedImage = selectedImage
        self.cleanupFailureCount = cleanupFailureCount
        self.retention = retention
        if window?.isVisible == true {
            render(destination: currentDestination)
        }
    }
}
