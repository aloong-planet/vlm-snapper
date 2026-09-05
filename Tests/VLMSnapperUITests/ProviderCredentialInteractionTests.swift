import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Provider credential interaction", .serialized)
@MainActor
struct ProviderCredentialInteractionTests {
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
        var key = initialKey
        var submitted: [String] = []
        func configuration() -> ProviderSettingsConfiguration {
            ProviderSettingsConfiguration(
                snapshot: ProviderSetupSnapshot(
                    selectedProvider: .deepSeek,
                    availableModelIDs: [], selectedModelID: nil,
                    phase: .awaitingValidation, failure: nil
                ),
                apiKey: Binding(get: { key }, set: { key = $0 }),
                pendingModelID: .constant(nil),
                onSelectProvider: { _ in },
                onValidate: { submitted.append(key) },
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
        #expect(key == "test-key")
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

        // Clear through the visible button and verify the previous enabled state
        // does not linger. Refill and submit with Return without ending editing.
        try click(window, at: NSPoint(x: fieldRect.maxX + 17, y: fieldRect.midY))
        settle(window)
        #expect(key == "")
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
        #expect(key == "second-key")
        let refreshedField = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        window.makeFirstResponder(refreshedField)
        let refreshedEditor = try #require(refreshedField.currentEditor() as? NSTextView)
        refreshedEditor.insertNewline(nil)
        settle(window)
        #expect(submitted == ["test-key", "second-key"])

        key = "loaded-key"
        controller.update(
            records: [], selectedRecordID: nil, selectedImage: nil,
            cleanupFailureCount: 0, retention: .thirtyDays,
            settings: GeneralSettingsSnapshot(), providerSettings: configuration()
        )
        settle(window)
        let loadedField = try #require(descendants(content).compactMap { $0 as? NSSecureTextField }.first)
        #expect(loadedField.stringValue == "loaded-key")

        key = ""
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
