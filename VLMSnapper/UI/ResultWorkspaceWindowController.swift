import AppKit
import SwiftUI
import VLMSnapperCore

@MainActor
public final class ResultWorkspaceWindowController: NSWindowController,
    NSWindowDelegate
{
    private let onClose: @MainActor () async -> WorkspaceCloseDisposition

    public init(
        onClose: @escaping @MainActor () async -> WorkspaceCloseDisposition
    ) {
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 520)
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public func show<Content: View>(content: Content) {
        window?.contentViewController = NSHostingController(rootView: content)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor [onClose] in
            let disposition = await onClose()
            if disposition != .confirmDiscardUnsavedResult {
                sender.orderOut(nil)
            }
        }
        return false
    }
}
