import AppKit
import CoreGraphics
import VLMSnapperCore

/// Reads the on-screen window list once per capture for snap regions (ADR-0014). Window
/// bounds need no extra permission; window names are not read.
struct CoreGraphicsCaptureWindowListing: CaptureWindowListing {
    func captureWindowSnapshot() async -> CaptureWindowSnapshot? {
        // Listing takes tens of milliseconds; keep it off the main thread so the overlay is not delayed.
        await Task.detached(priority: .userInitiated) {
            guard let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]] else { return nil }
            let windows = list.compactMap { info -> CaptureWindowSnapshotEntry? in
                guard let process = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                      let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                      let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { return nil }
                return CaptureWindowSnapshotEntry(
                    ownerProcessID: process,
                    layer: layer,
                    alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                    isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true,
                    bounds: bounds
                )
            }
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
                .first?.processIdentifier
            return CaptureWindowSnapshot(windows: windows, dockProcessID: dock)
        }.value
    }
}
