import AppKit
import UniformTypeIdentifiers

/// Puts a captured image on the clipboard (v1-core::REQ-008).
@MainActor
protocol CaptureImageClipboard {
    /// Returns `false` when the clipboard did not take the image.
    func write(png: Data) -> Bool
}

enum CaptureImageSaveOutcome: Equatable {
    case saved(URL)
    case cancelled
    case failed
}

/// Asks where to save a captured image and writes it there (v1-core::REQ-009).
@MainActor
protocol CaptureImageSaving {
    func save(png: Data, suggestedName: String) async -> CaptureImageSaveOutcome
}

struct SystemCaptureImageClipboard: CaptureImageClipboard {
    func write(png: Data) -> Bool {
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png) else { return false }
        // A TIFF representation next to the PNG lets apps that read either type paste the image.
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

struct SavePanelCaptureImageSaver: CaptureImageSaving {
    private static let savedBeforeKey = "captureImageSavedBefore"

    func save(png: Data, suggestedName: String) async -> CaptureImageSaveOutcome {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        // The first save starts in Pictures; later ones open where the panel was last used.
        if !UserDefaults.standard.bool(forKey: Self.savedBeforeKey),
           let pictures = try? ApplicationDirectories.screenshotRoot()
            .deletingLastPathComponent()
            .resolvingSymlinksInPath() {
            panel.directoryURL = pictures
        }
        // Above the capture overlay, which sits at the screen saver level. `runModal` would move the
        // panel back to the modal-panel level, under the overlay (measured 2026-10-29: layer 8 under
        // 1000), so the panel is shown without a modal session and keeps this level.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let url = panel.url else { return .cancelled }
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            return .failed
        }
        UserDefaults.standard.set(true, forKey: Self.savedBeforeKey)
        return .saved(url)
    }
}

enum CaptureImageFileName {
    /// `vlmsnapper-yyyyMMdd-HHmmss.png`, the same pattern as saved screenshots.
    static func suggested(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "vlmsnapper-\(formatter.string(from: date)).png"
    }
}
