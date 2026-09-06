import AppKit
import SwiftUI
import VLMSnapperCore
import VLMSnapperUI

// Real AppKit menu tracking needs the application event loop, not SwiftPM's
// test runner. All values and the private clipboard are owned by this fixture.
@MainActor
final class ProviderEditingSmoke: NSObject {
    private let credential = ProviderCredentialEditor(loadedValue: "old-suffix")
    private var controller: ManagementCenterWindowController?
    private var trackedMenu: NSMenu?
    private let board = NSPasteboard.withUniqueName()

    func run() {
        checkpoint("create-window")
        if NSApp.activationPolicy() != .regular {
            check(NSApp.setActivationPolicy(.regular), "cannot activate standalone UI harness")
        }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        NSApp.mainMenu = VLMSnapperApplicationMenuBuilder.makeMainMenu(
            applicationName: "VLMSnapperUIHarness", pasteboard: board
        )
        controller = ManagementCenterWindowController(
            records: [], providerSettings: ProviderSettingsConfiguration(
                snapshot: ProviderSetupSnapshot(
                    selectedProvider: .deepSeek, availableModelIDs: [],
                    selectedModelID: nil, phase: .awaitingValidation, failure: nil
                ),
                credentialEditor: credential,
                pendingModelID: .constant(nil), onSelectProvider: { _ in },
                onValidate: { _ in }, onRefresh: {}, onSelectModel: { _ in }
            )
        )
        controller?.show(destination: .providerSettings)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows where window !== self.controller?.window {
                window.orderOut(nil)
            }
            self.controller?.window?.makeKeyAndOrderFront(nil)
            self.controller?.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            self.waitForKeyWindow(attempt: 0)
        }
    }

    private func waitForKeyWindow(attempt: Int) {
        if NSApp.isActive {
            controller?.window?.makeKeyAndOrderFront(nil)
            controller?.window?.makeKey()
        }
        if NSApp.keyWindow === controller?.window {
            checkpoint("window-is-key")
            exerciseContextMenu()
        } else if attempt < 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.waitForKeyWindow(attempt: attempt + 1)
            }
        } else {
            check(false, "production window did not become key within 10 seconds")
        }
    }

    private func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("PROVIDER_EDITING_SMOKE_FAIL: \(message)")
            board.releaseGlobally()
            exit(1)
        }
    }

    private func checkpoint(_ stage: String) {
        FileHandle.standardOutput.write(Data("PROVIDER_EDITING_SMOKE_STAGE: \(stage)\n".utf8))
    }

    private func exerciseContextMenu() {
        guard let window = controller?.window, let content = window.contentView,
              let field = descendants(content).compactMap({ $0 as? NSSecureTextField }).first else {
            check(false, "missing production secure field")
            return
        }
        check(NSApp.keyWindow === window, "production window is not key")
        check(window.makeFirstResponder(field), "cannot focus secure field")
        guard let editor = field.currentEditor() as? NSTextView else {
            check(false, "missing system field editor")
            return
        }
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        board.setString(" new\t\r\n", forType: .string)
        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown, location: field.convert(NSPoint(x: 4, y: field.bounds.midY), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ), let menu = editor.menu(for: event),
           let paste = menu.items.first(where: { $0.action == #selector(NSText.paste(_:)) }) else {
            check(false, "missing native Paste menu item")
            return
        }
        trackedMenu = menu
        checkpoint("track-context-menu")
        // Close the real popup through the run loop so this test is unattended.
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(closeMenu),
                          userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        menu.popUp(positioning: nil, at: NSPoint(x: 20, y: 20), in: field)
        timer.invalidate()
        check(NSApp.keyWindow === window, "context menu changed key window")
        checkpoint("invoke-context-paste")
        menu.performActionForItem(at: menu.index(of: paste))
        check(Array(credential.value.utf8) == Array(" new\t-suffix".utf8), "context Paste did not normalize at the insertion boundary")
        check(editor.selectedRange() == NSRange(location: 5, length: 0), "context Paste misplaced the caret")
        check(board.string(forType: .string) == " new\t\r\n", "clipboard was modified")
        print("PROVIDER_EDITING_SMOKE_PASS: native secure context Paste")
        board.releaseGlobally()
        exit(0)
    }

    @objc private func closeMenu() { trackedMenu?.cancelTracking() }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
