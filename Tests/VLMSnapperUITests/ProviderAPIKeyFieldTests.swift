import AppKit
import Testing
@testable import VLMSnapperUI

// Field/menu APIs are exercised with dummy data. Physical keyboard/mouse and
// signed installed-app acceptance are separate; context tracking uses the runner.
@Suite("Native Provider API Key editing", .serialized)
@MainActor
struct ProviderAPIKeyFieldTests {
    @Test("accessibility edits update the credential without submitting", arguments: [false, true])
    func accessibilityEditsReachBinding(revealed: Bool) {
        let field = ProviderAPIKeyInputView(frame: .zero)
        var value = "old"
        var submissions = 0
        field.onValueChange = { value = $0 }
        field.onSubmit = { submissions += 1 }
        field.update(value: "old", placeholder: "API Key", revealed: revealed, enabled: true)

        field.activeField.setAccessibilityValue(" e\u{301}-key\t ")

        #expect(Array(value.utf8) == [32, 101, 204, 129, 45, 107, 101, 121, 9, 32])
        #expect(Array(field.activeField.stringValue.utf8) == [32, 101, 204, 129, 45, 107, 101, 121, 9, 32])
        #expect(submissions == 0)
    }

    @Test("accessibility writes respect unavailable fields", arguments: [false, true])
    func accessibilityRejectsUnavailableFields(revealed: Bool) {
        let field = ProviderAPIKeyInputView(frame: .zero)
        var edits = [String]()
        field.onValueChange = { edits.append($0) }
        field.update(value: "original", placeholder: "API Key", revealed: revealed, enabled: false)
        let originalField = field.activeField
        originalField.setAccessibilityValue("disabled-edit")
        #expect(originalField.stringValue == "original")

        field.update(value: "original", placeholder: "API Key", revealed: revealed, enabled: true)
        originalField.isEditable = false
        originalField.setAccessibilityValue("read-only-edit")
        #expect(originalField.stringValue == "original")

        field.update(value: "original", placeholder: "API Key", revealed: !revealed, enabled: true)
        originalField.setAccessibilityValue("hidden-edit")
        #expect(originalField.stringValue == "original")
        #expect(field.activeField.stringValue == "original")

        field.isHidden = true
        field.activeField.setAccessibilityValue("hidden-parent-edit")
        #expect(field.activeField.stringValue == "original")
        #expect(edits.isEmpty)
    }

    @Test("accessibility clearing is an edit but loading and invalid types are not", arguments: [false, true])
    func accessibilityClearingAndReload(revealed: Bool) {
        let field = ProviderAPIKeyInputView(frame: .zero)
        var edits = [String]()
        field.onValueChange = { edits.append($0) }
        field.update(value: "loaded", placeholder: "API Key", revealed: revealed, enabled: true)
        field.activeField.setAccessibilityValue(nil)
        field.activeField.setAccessibilityValue(42)
        #expect(field.activeField.stringValue == "loaded")
        #expect(edits.isEmpty)

        field.activeField.setAccessibilityValue("")
        #expect(field.activeField.stringValue == "")
        #expect(edits == [""])
        field.update(value: "reloaded", placeholder: "API Key", revealed: !revealed, enabled: true)
        #expect(field.activeField.stringValue == "reloaded")
        #expect(edits == [""])
    }

    @Test("accessibility edits keep an attached system editor synchronized", arguments: [false, true])
    func accessibilityEditsWithSystemEditor(revealed: Bool) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = ProviderAPIKeyInputView(frame: NSRect(x: 10, y: 10, width: 300, height: 40))
        window.contentView?.addSubview(field)
        defer { window.orderOut(nil) }
        var value = "old-key"
        field.onValueChange = { value = $0 }
        field.update(value: "old-key", placeholder: "API Key", revealed: revealed, enabled: true)
        #expect(window.makeFirstResponder(field.activeField))
        let editor = try #require(field.activeField.currentEditor() as? NSTextView)
        field.activeField.setAccessibilityValue("new-key")
        #expect(editor.string == "new-key")
        #expect(window.firstResponder === editor)
        editor.insertText("!", replacementRange: NSRange(location: 7, length: 0))
        #expect(value == "new-key!")
        #expect(field.activeField.stringValue == "new-key!")
    }

    @Test("paste normalization preserves all content except one trailing CRLF LF or CR",
          arguments: [
            ("X\n", "X"), ("X\r", "X"), ("X\r\n", "X"),
            ("X\n\n", "X\n"), (" X\t ", " X\t "),
            ("e\u{301}", "e\u{301}"), ("x\nY", "x\nY"),
          ])
    func pasteNormalizationIsNarrow(input: String, expected: String) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = ProviderAPIKeyInputView(frame: NSRect(x: 10, y: 10, width: 300, height: 40))
        window.contentView?.addSubview(field)
        defer { window.orderOut(nil) }
        field.update(value: "", placeholder: "API Key", revealed: false, enabled: true)
        #expect(window.makeFirstResponder(field.activeField))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(input, forType: .string)
        field.paste(from: board)
        #expect(Array(field.activeField.stringValue.utf8) == Array(expected.utf8))
        #expect(board.string(forType: .string)?.utf8.elementsEqual(input.utf8) == true)
    }

    @Test("visibility changes keep the system editor selection and exact value")
    func visibilityPreservesSelection() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = ProviderAPIKeyInputView(frame: NSRect(x: 10, y: 10, width: 300, height: 40))
        window.contentView?.addSubview(field)
        defer { window.orderOut(nil) }
        var edits = [String]()
        var submissions = 0
        field.onValueChange = { edits.append($0) }
        field.onSubmit = { submissions += 1 }
        field.update(value: " e\u{301}🔑-key ", placeholder: "API Key", revealed: false, enabled: true)
        #expect(window.makeFirstResponder(field.activeField))
        let secureEditor = try #require(field.activeField.currentEditor())
        secureEditor.selectedRange = NSRange(location: 1, length: 4)
        field.update(value: " e\u{301}🔑-key ", placeholder: "API Key", revealed: true, enabled: true)
        #expect(!(field.activeField is NSSecureTextField))
        #expect(field.activeField.currentEditor()?.selectedRange == NSRange(location: 1, length: 4))
        #expect(Array(field.activeField.stringValue.utf8) == [32, 101, 204, 129, 240, 159, 148, 145, 45, 107, 101, 121, 32])
        field.update(value: " e\u{301}🔑-key ", placeholder: "API Key", revealed: false, enabled: true)
        #expect(field.activeField is NSSecureTextField)
        #expect(field.activeField.currentEditor()?.selectedRange == NSRange(location: 1, length: 4))
        #expect(field.activeField.placeholderString == "")
        #expect(edits.isEmpty)
        #expect(submissions == 0)
        // A late authoritative reload can shorten the value in the same render
        // that resets visibility. AppKit must keep its selection in bounds.
        field.update(value: "x", placeholder: "API Key", revealed: true, enabled: true)
        #expect(field.activeField.currentEditor()?.selectedRange == NSRange(location: 1, length: 0))
        #expect(field.activeField.stringValue == "x")
        #expect(edits.isEmpty)
        #expect(submissions == 0)
    }

    // Native context-menu tracking requires NSApplication.run; the executable
    // UI harness covers it and must report an explicit smoke-test PASS marker.
    @Test("standard keyboard paste removes one trailing sequence", arguments: [false, true])
    func standardPasteRoutes(revealed: Bool) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = ProviderAPIKeyInputView(frame: NSRect(x: 10, y: 10, width: 300, height: 40))
        window.contentView?.addSubview(field)
        defer { window.orderOut(nil) }
        field.update(value: "old-suffix", placeholder: "API Key", revealed: revealed, enabled: true)
        #expect(window.makeFirstResponder(field.activeField))
        let editor = try #require(field.activeField.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(" new\t\r\n", forType: .string)
        let mainMenu = VLMSnapperApplicationMenuBuilder.makeMainMenu(
            applicationName: "VLMSnapper", pasteboard: board,
            activeResponder: { window.firstResponder }
        )
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "v",
            charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9
        ))
        #expect(mainMenu.performKeyEquivalent(with: event))
        #expect(field.activeField.stringValue == " new\t-suffix")
        #expect(editor.selectedRange() == NSRange(location: 5, length: 0))
        #expect(board.string(forType: .string) == " new\t\r\n")
        withExtendedLifetime(mainMenu) {}
    }
}
