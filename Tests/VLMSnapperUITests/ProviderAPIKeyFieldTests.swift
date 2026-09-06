import AppKit
import Testing
@testable import VLMSnapperUI

// Field/menu APIs are exercised with dummy data. Physical keyboard/mouse and
// signed installed-app acceptance are separate; context tracking uses the runner.
@Suite("Native Provider API Key editing", .serialized)
@MainActor
struct ProviderAPIKeyFieldTests {
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
