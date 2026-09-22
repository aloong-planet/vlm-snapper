import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

// Uses programmatic AppKit editor events on the production window. Button
// actions are covered by Scripts/test-provider-accessibility.py, not coordinates.
// Physical input,
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

    @Test("unsafe typed keys cannot be submitted by Return",
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
        "typed and pasted credentials submit once via Return and survive window refreshes",
        arguments: ["", "initial-key"], [false, true]
    )
    func editsSubmitViaReturn(initialKey: String, paste: Bool) throws {
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
        try submitReturn(editor, in: window)
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

        // Editing to empty is distinct from the AX Clear button scenario.
        submittedEditor.insertText("", replacementRange: NSRange(location: 0, length: submittedEditor.string.utf16.count))
        settle(window)
        #expect(credential.value == "")
        try submitReturn(submittedEditor, in: window)
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
        #expect(window.makeFirstResponder(loadedField))
        try submitReturn(try #require(loadedField.currentEditor() as? NSTextView), in: window)
        settle(window)
        #expect(submitted == ["test-key", "second-key"])
    }

    @Test("another active Provider job permits native editing but blocks Return until it ends")
    func otherProviderJobBlocksNativeSubmission() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let credential = ProviderCredentialEditor(loadedValue: "")
        var submissions: [String] = []
        func configuration(blocked: Bool) -> ProviderSettingsConfiguration {
            ProviderSettingsConfiguration(
                snapshot: ProviderSetupSnapshot(selectedProvider: .deepSeek, availableModelIDs: [],
                    selectedModelID: nil, phase: .awaitingValidation, failure: nil,
                    activity: blocked ? .credential(.openAI) : nil),
                credentialEditor: credential, pendingModelID: .constant(nil),
                onSelectProvider: { _ in }, onValidate: { submissions.append($0.value) },
                onRefresh: {}, onSelectModel: { _ in }
            )
        }
        let controller = ManagementCenterWindowController(records: [], providerSettings: configuration(blocked: true))
        controller.show(destination: .providerSettings)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        settle(window)
        let content = try #require(window.contentView)
        let field = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(field.isEnabled)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("draft-fixture", replacementRange: editor.selectedRange())
        settle(window)
        #expect(credential.value == "draft-fixture")
        let focusedEditor = try #require(field.currentEditor() as? NSTextView)
        focusedEditor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        settle(window)
        #expect(submissions.isEmpty)
        controller.update(records: [], selectedRecordID: nil, selectedImage: nil,
                          cleanupFailureCount: 0, retention: .thirtyDays,
                          settings: GeneralSettingsSnapshot(), providerSettings: configuration(blocked: false))
        settle(window)
        #expect(credential.value == "draft-fixture")
        let enabledField = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(window.makeFirstResponder(enabledField))
        try submitReturn(try #require(enabledField.currentEditor() as? NSTextView), in: window)
        settle(window)
        #expect(submissions == ["draft-fixture"])
    }

    @Test("an explicit active-job focus request navigates an existing history window to that Provider")
    func activeJobFocusNavigatesExistingWindow() throws {
        let credential = ProviderCredentialEditor(loadedValue: "")
        func configuration(target: ProviderID, focus: ProviderSettingsFocusRequest?) -> ProviderSettingsConfiguration {
            ProviderSettingsConfiguration(
                snapshot: ProviderSetupSnapshot(selectedProvider: target, availableModelIDs: [],
                    selectedModelID: nil, phase: .validating, failure: nil, isReadOnly: true,
                    activity: .credential(target)), focusRequest: focus,
                credentialEditor: credential, pendingModelID: .constant(nil),
                onSelectProvider: { _ in }, onValidate: { _ in }, onRefresh: {}, onSelectModel: { _ in }
            )
        }
        let controller = ManagementCenterWindowController(records: [], providerSettings: configuration(target: .deepSeek, focus: nil))
        controller.show(destination: .history)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        settle(window)
        let content = try #require(window.contentView)
        #expect(descendants(content).compactMap { $0 as? NSSecureTextField }.isEmpty)
        let load = credential.beginLoading(for: .openAI)
        credential.completeLoad(load, value: "active-fixture")
        controller.update(records: [], selectedRecordID: nil, selectedImage: nil,
            cleanupFailureCount: 0, retention: .thirtyDays, settings: GeneralSettingsSnapshot(),
            providerSettings: configuration(target: .openAI, focus: ProviderSettingsFocusRequest(provider: .openAI)))
        controller.show(destination: .providerSettings)
        settle(window)
        let field = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(field.stringValue == "active-fixture")
        #expect(!field.isEnabled)
        #expect(content.bounds.intersects(field.convert(field.bounds, to: content)))
    }

    private func settle(_ window: NSWindow) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func submitReturn(_ editor: NSTextView, in window: NSWindow) throws {
        editor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
    }
}
