import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

// Uses programmatic AppKit events on the production window. Physical input,
// signed-app Keychain access and real Provider calls require separate acceptance.
@Suite("Provider credential interaction", .serialized)
@MainActor
struct ProviderCredentialInteractionTests {
    @Test("closing and reopening the production window reloads instead of retaining a draft")
    func windowCloseDiscardsDraft() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let credential = ProviderCredentialEditor(loadedValue: "saved-key")
        let controller = ManagementCenterWindowController(records: [], providerSettings: ProviderSettingsConfiguration(
            snapshot: ProviderSetupSnapshot(selectedProvider: .deepSeek, availableModelIDs: [],
                                            selectedModelID: nil, phase: .awaitingValidation, failure: nil),
            credentialEditor: credential, pendingModelID: .constant(nil),
            onSelectProvider: { provider in
                let read = credential.beginLoading(for: provider)
                credential.completeLoad(read, value: "saved-key")
            },
            onValidate: { _ in Issue.record("Reopening must not validate") },
            onRefresh: {}, onSelectModel: { _ in }
        ))
        controller.show(destination: .providerSettings)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        settle(window)
        let content = try #require(window.contentView)
        let field = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("unsaved-key", replacementRange: NSRange(location: 0, length: 9))
        settle(window)
        #expect(credential.isDirty)
        window.performClose(nil)
        settle(window)
        #expect(!credential.isOpen)
        #expect(credential.value.isEmpty)
        controller.show(destination: .providerSettings)
        settle(window)
        let reopenedField = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(reopenedField.stringValue == "saved-key")
        #expect(!credential.isDirty)
    }

    @Test("reverting a loaded credential prevents Return from resubmitting it")
    func revertedCredentialCannotSubmit() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let credential = ProviderCredentialEditor(loadedValue: "loaded-key")
        var submissions = 0
        let controller = ManagementCenterWindowController(records: [], providerSettings: ProviderSettingsConfiguration(
            snapshot: ProviderSetupSnapshot(selectedProvider: .deepSeek, availableModelIDs: [],
                                            selectedModelID: nil, phase: .awaitingValidation, failure: nil),
            credentialEditor: credential, pendingModelID: .constant(nil),
            onSelectProvider: { _ in }, onValidate: { submission in
                submissions += 1
                credential.complete(submission, succeeded: true)
            },
            onRefresh: {}, onSelectModel: { _ in }
        ))
        controller.show(destination: .providerSettings)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        settle(window)
        let content = try #require(window.contentView)
        let field = try #require(descendants(content)
            .compactMap { $0 as? NSSecureTextField }.first)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("changed-key", replacementRange: NSRange(location: 0, length: 10))
        settle(window)
        editor.insertText("loaded-key", replacementRange: NSRange(location: 0, length: 11))
        settle(window)
        #expect(credential.value == "loaded-key")
        editor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        settle(window)
        #expect(submissions == 0)
    }

    @Test("unsafe typed keys cannot be submitted by Validate or Return",
          arguments: ["key\nvalue", "key\r", String(repeating: "x", count: 4097)])
    func unsafeDraftCannotValidate(value: String) throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let credential = ProviderCredentialEditor(loadedValue: "")
        var submissions = 0
        let controller = ManagementCenterWindowController(records: [], providerSettings: ProviderSettingsConfiguration(
            snapshot: ProviderSetupSnapshot(selectedProvider: .deepSeek, availableModelIDs: [],
                                            selectedModelID: nil, phase: .awaitingValidation, failure: nil),
            credentialEditor: credential, pendingModelID: .constant(nil),
            onSelectProvider: { _ in }, onValidate: { submission in
                submissions += 1
                credential.complete(submission, succeeded: true)
            },
            onRefresh: {}, onSelectModel: { _ in }
        ))
        controller.show(destination: .providerSettings)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        settle(window)
        let content = try #require(window.contentView)
        let field = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText(value, replacementRange: editor.selectedRange())
        settle(window)
        #expect(Array(credential.value.utf8) == Array(value.utf8))
        let rect = field.convert(field.bounds, to: nil)
        try click(window, at: NSPoint(x: content.bounds.width - 75, y: rect.minY - 30))
        window.makeFirstResponder(field)
        editor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        settle(window)
        #expect(submissions == 0)
    }

    @Test("system paste preserves opaque text and removes just one trailing newline")
    func pasteReplacesSelectionWithoutTrimming() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let credential = ProviderCredentialEditor(loadedValue: "old-suffix")
        let controller = ManagementCenterWindowController(
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
        controller.show(destination: .providerSettings)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        settle(window)
        let content = try #require(window.contentView)
        let field = try #require(descendants(content)
            .compactMap { $0 as? NSSecureTextField }.first)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(" new\t\r\n", forType: .string)
        let menu = VLMSnapperApplicationMenuBuilder.makeMainMenu(
            applicationName: "VLMSnapper", pasteboard: board,
            activeResponder: { window.firstResponder }
        )
        let edit = try #require(menu.item(withTitle: "Edit")?.submenu)
        #expect(window.firstResponder === editor)
        edit.performActionForItem(at: try #require(edit.items.firstIndex { $0.action == #selector(NSText.paste(_:)) }))
        settle(window)
        #expect(Array(credential.value.utf8) == Array(" new\t-suffix".utf8))
        #expect(editor.selectedRange() == NSRange(location: 5, length: 0))
    }

    // These tests exercise the production window and AppKit editor. Network and
    // Keychain effects stop at the public validation callback; no real key is used.
    @Test(
        "credential edits, clearing, and window refreshes keep validation coherent",
        arguments: ["", "initial-key"], [false, true]
    )
    func editingEnablesValidation(initialKey: String, paste: Bool) throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let credential = ProviderCredentialEditor(loadedValue: initialKey)
        var submitted: [String] = []
        func configuration() -> ProviderSettingsConfiguration {
            ProviderSettingsConfiguration(
                snapshot: ProviderSetupSnapshot(
                    selectedProvider: .deepSeek,
                    availableModelIDs: [], selectedModelID: nil,
                    phase: .awaitingValidation, failure: nil
                ),
                credentialEditor: credential,
                pendingModelID: .constant(nil),
                onSelectProvider: { _ in },
                onValidate: { submission in
                    #expect(submission.provider == .deepSeek)
                    submitted.append(submission.value)
                    credential.complete(submission, succeeded: true)
                },
                onRefresh: {}, onSelectModel: { _ in }
            )
        }
        let controller = ManagementCenterWindowController(
            records: [], providerSettings: configuration()
        )
        controller.show(destination: .providerSettings)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        settle(window)
        let content = try #require(window.contentView)
        let field = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        if paste {
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            pasteboard.setString("test-key", forType: .string)
            #expect(editor.readSelection(from: pasteboard))
        } else {
            editor.insertText("test-key", replacementRange: editor.selectedRange())
        }
        settle(window)
        #expect(credential.value == "test-key")
        let fieldRect = field.convert(field.bounds, to: nil)
        // These points target the confirmed minimum-width layout. The prefilled
        // positive control proves the same hit test can reach Validate.
        let point = NSPoint(x: content.bounds.width - 75, y: fieldRect.minY - 30)
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: "/private/tmp/vlmsnapper-credential-\(initialKey.isEmpty ? "empty" : "prefilled").png")
        )
        try click(window, at: point)
        settle(window)
        #expect(submitted == ["test-key"])

        window.makeFirstResponder(field)
        let submittedEditor = try #require(field.currentEditor() as? NSTextView)
        submittedEditor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        settle(window)
        #expect(submitted == ["test-key"])

        // Clear through the visible button and verify the previous enabled state
        // does not linger. Refill and submit with Return without ending editing.
        try click(window, at: NSPoint(x: fieldRect.maxX + 17, y: fieldRect.midY))
        settle(window)
        #expect(credential.value == "")
        try click(window, at: point)
        settle(window)
        #expect(submitted == ["test-key"])

        window.makeFirstResponder(field)
        let secondEditor = try #require(field.currentEditor() as? NSTextView)
        secondEditor.insertText("second-key", replacementRange: secondEditor.selectedRange())
        settle(window)
        controller.update(
            records: [], selectedRecordID: nil, selectedImage: nil,
            cleanupFailureCount: 0, retention: .thirtyDays,
            settings: GeneralSettingsSnapshot(), providerSettings: configuration()
        )
        settle(window)
        #expect(credential.value == "second-key")
        let refreshedField = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        window.makeFirstResponder(refreshedField)
        let refreshedEditor = try #require(refreshedField.currentEditor() as? NSTextView)
        refreshedEditor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        settle(window)
        #expect(submitted == ["test-key", "second-key"])

        credential.load("loaded-key")
        controller.update(
            records: [], selectedRecordID: nil, selectedImage: nil,
            cleanupFailureCount: 0, retention: .thirtyDays,
            settings: GeneralSettingsSnapshot(), providerSettings: configuration()
        )
        settle(window)
        let loadedField = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(loadedField.stringValue == "loaded-key")

        credential.load("")
        controller.update(
            records: [], selectedRecordID: nil, selectedImage: nil,
            cleanupFailureCount: 0, retention: .thirtyDays,
            settings: GeneralSettingsSnapshot(), providerSettings: configuration()
        )
        settle(window)
        #expect(loadedField.stringValue == "")
        try click(window, at: point)
        settle(window)
        #expect(submitted == ["test-key", "second-key"])
    }

    private func settle(_ window: NSWindow) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func click(_ window: NSWindow, at point: NSPoint) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )))
        }
    }
}
