import AppKit
import SwiftUI
import VLMSnapperCore

@MainActor
public final class ResultWorkspaceWindowController: NSWindowController,
    NSWindowDelegate
{
    private let onClose: @MainActor () async -> WorkspaceCloseDisposition
    private let onDiscardUnsaved: @MainActor () async -> Void

    public init(
        onClose: @escaping @MainActor () async -> WorkspaceCloseDisposition,
        onDiscardUnsaved: @escaping @MainActor () async -> Void
    ) {
        self.onClose = onClose
        self.onDiscardUnsaved = onDiscardUnsaved
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .normal
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

    public func present<Content: View>(content: Content) {
        window?.contentViewController = NSHostingController(rootView: content)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func update<Content: View>(content: Content) {
        window?.contentViewController = NSHostingController(rootView: content)
    }

    public func hideForCapture() {
        window?.orderOut(nil)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor [onClose] in
            let disposition = await onClose()
            if disposition == .confirmDiscardUnsavedResult {
                guard UnsavedResultConfirmation.confirm() else { return }
                await onDiscardUnsaved()
                sender.orderOut(nil)
            } else {
                sender.orderOut(nil)
            }
        }
        return false
    }
}

@MainActor
public enum UnsavedResultConfirmation {
    public static func confirm() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = VLMSnapperStrings.discardUnsavedTitle
        alert.informativeText = VLMSnapperStrings.discardUnsavedBody
        alert.addButton(withTitle: VLMSnapperStrings.discardUnsavedAction)
        alert.addButton(withTitle: VLMSnapperStrings.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
