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
        try settle(window) { secureField(in: window)?.stringValue == "saved-key" }
        let content = try #require(window.contentView)
        let field = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("unsaved-key", replacementRange: NSRange(location: 0, length: 9))
        try settle(window) { credential.isDirty && field.stringValue == "unsaved-key" }
        #expect(credential.isDirty)
        window.performClose(nil)
        try settle(window) { !credential.isOpen && credential.value.isEmpty }
        #expect(!credential.isOpen)
        #expect(credential.value.isEmpty)
        controller.show(destination: .providerSettings)
        try settle(window) { secureField(in: window)?.stringValue == "saved-key" && !credential.isDirty }
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
        try settle(window) { secureField(in: window)?.stringValue == "loaded-key" }
        let content = try #require(window.contentView)
        let field = try #require(descendants(content)
            .compactMap { $0 as? NSSecureTextField }.first)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("changed-key", replacementRange: NSRange(location: 0, length: 10))
        try settle(window) { credential.value == "changed-key" && field.stringValue == "changed-key" }
        editor.insertText("loaded-key", replacementRange: NSRange(location: 0, length: 11))
        try settle(window) { credential.value == "loaded-key" && field.stringValue == "loaded-key" }
        #expect(credential.value == "loaded-key")
        editor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        layout(window)
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
        try settle(window) { secureField(in: window) != nil }
        let content = try #require(window.contentView)
        let field = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText(value, replacementRange: editor.selectedRange())
        try settle(window) { credential.value.utf8.elementsEqual(value.utf8) && field.stringValue.utf8.elementsEqual(value.utf8) }
        #expect(Array(credential.value.utf8) == Array(value.utf8))
        editor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        layout(window)
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
        try settle(window) { secureField(in: window)?.stringValue == "old-suffix" }
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
        try settle(window) { credential.value == " new\t-suffix" && editor.selectedRange() == NSRange(location: 5, length: 0) }
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
        try settle(window) { secureField(in: window)?.stringValue == initialKey }
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
        try settle(window) { credential.value == "test-key" && field.stringValue == "test-key" }
        #expect(credential.value == "test-key")
        try submitReturn(editor, in: window)
        try settle(window) { submitted == ["test-key"] }
        #expect(submitted == ["test-key"])

        window.makeFirstResponder(field)
        let submittedEditor = try #require(field.currentEditor() as? NSTextView)
        submittedEditor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        layout(window)
        #expect(submitted == ["test-key"])

        // Editing to empty is distinct from the AX Clear button scenario.
        submittedEditor.insertText("", replacementRange: NSRange(location: 0, length: submittedEditor.string.utf16.count))
        try settle(window) { credential.value.isEmpty && field.stringValue.isEmpty }
        #expect(credential.value == "")
        try submitReturn(submittedEditor, in: window)
        layout(window)
        #expect(submitted == ["test-key"])

        window.makeFirstResponder(field)
        let secondEditor = try #require(field.currentEditor() as? NSTextView)
        secondEditor.insertText("second-key", replacementRange: secondEditor.selectedRange())
        try settle(window) { credential.value == "second-key" && field.stringValue == "second-key" }
        controller.update(
            records: [], selectedRecordID: nil, selectedImage: nil,
            cleanupFailureCount: 0, retention: .thirtyDays,
            settings: GeneralSettingsSnapshot(), providerSettings: configuration()
        )
        try settle(window) { credential.value == "second-key" && secureField(in: window)?.stringValue == "second-key" }
        #expect(credential.value == "second-key")
        let refreshedField = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        window.makeFirstResponder(refreshedField)
        let refreshedEditor = try #require(refreshedField.currentEditor() as? NSTextView)
        refreshedEditor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        try settle(window) { submitted == ["test-key", "second-key"] }
        #expect(submitted == ["test-key", "second-key"])

        credential.load("loaded-key")
        controller.update(
            records: [], selectedRecordID: nil, selectedImage: nil,
            cleanupFailureCount: 0, retention: .thirtyDays,
            settings: GeneralSettingsSnapshot(), providerSettings: configuration()
        )
        try settle(window) { secureField(in: window)?.stringValue == "loaded-key" }
        let loadedField = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(loadedField.stringValue == "loaded-key")

        credential.load("")
        controller.update(
            records: [], selectedRecordID: nil, selectedImage: nil,
            cleanupFailureCount: 0, retention: .thirtyDays,
            settings: GeneralSettingsSnapshot(), providerSettings: configuration()
        )
        try settle(window) { loadedField.stringValue.isEmpty }
        #expect(loadedField.stringValue == "")
        #expect(window.makeFirstResponder(loadedField))
        try submitReturn(try #require(loadedField.currentEditor() as? NSTextView), in: window)
        layout(window)
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
        try settle(window) { secureField(in: window) != nil }
        let content = try #require(window.contentView)
        let field = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(field.isEnabled)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("draft-fixture", replacementRange: editor.selectedRange())
        try settle(window) { credential.value == "draft-fixture" && field.stringValue == "draft-fixture" }
        #expect(credential.value == "draft-fixture")
        let focusedEditor = try #require(field.currentEditor() as? NSTextView)
        focusedEditor.interpretKeyEvents([try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))])
        layout(window)
        #expect(submissions.isEmpty)
        controller.update(records: [], selectedRecordID: nil, selectedImage: nil,
                          cleanupFailureCount: 0, retention: .thirtyDays,
                          settings: GeneralSettingsSnapshot(), providerSettings: configuration(blocked: false))
        try settle(window) { secureField(in: window)?.isEnabled == true && credential.value == "draft-fixture" }
        #expect(credential.value == "draft-fixture")
        let enabledField = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(window.makeFirstResponder(enabledField))
        try submitReturn(try #require(enabledField.currentEditor() as? NSTextView), in: window)
        try settle(window) { submissions == ["draft-fixture"] }
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
        layout(window)
        let content = try #require(window.contentView)
        #expect(descendants(content).compactMap { $0 as? NSSecureTextField }.isEmpty)
        let load = credential.beginLoading(for: .openAI)
        credential.completeLoad(load, value: "active-fixture")
        controller.update(records: [], selectedRecordID: nil, selectedImage: nil,
            cleanupFailureCount: 0, retention: .thirtyDays, settings: GeneralSettingsSnapshot(),
            providerSettings: configuration(target: .openAI, focus: ProviderSettingsFocusRequest(provider: .openAI)))
        controller.show(destination: .providerSettings)
        try settle(window) { secureField(in: window)?.stringValue == "active-fixture" && secureField(in: window)?.isEnabled == false }
        let field = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(field.stringValue == "active-fixture")
        #expect(!field.isEnabled)
        #expect(content.bounds.intersects(field.convert(field.bounds, to: content)))
    }

    private func settle(_ window: NSWindow, until predicate: () -> Bool) throws {
        try #require(waitForNativeCondition(timeout: 0.05) {
            layout(window)
            return predicate()
        }, "Provider UI condition did not settle within 50 ms")
    }

    // Return submission is synchronous through the NSTextField delegate. Keep
    // negative assertions direct, rather than polling an initially true count.
    private func layout(_ window: NSWindow) {
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func secureField(in window: NSWindow) -> NSSecureTextField? {
        guard let content = window.contentView else { return nil }
        return descendants(content).compactMap { $0 as? NSSecureTextField }
            .first { !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 }
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
