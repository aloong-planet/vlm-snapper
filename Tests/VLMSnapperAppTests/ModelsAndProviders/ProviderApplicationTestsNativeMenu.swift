import AppKit
import Foundation
import SwiftUI
import Testing
import XCTest
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// The XCTest case below owns real key-window activation and main-menu Paste.
// It is still programmatic input, not installed-app physical Cmd+V acceptance.
// Closed-window completion is observed from the actual onboarding view render;
// this is not desktop capture or an occlusion/physical-focus check.
// CI and the local gate run each of these cases in its own process. Same-process
// repeats cover fixture teardown without relying on process exit to release the
// native view graph.
// Wait traces are diagnostic only: observation can affect scheduling, and a
// process abort before the deferred flush can lose the buffered transitions.
// Historical intermittent deadlines still need a failing, instrumented run.
@MainActor
final class ProviderApplicationTestsNativeMenu: XCTestCase {

    func testThrownNativeOperationReleasesViewsWithoutChangingExistingWindows() async throws {
        let existing = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                styleMask: [.titled], backing: .buffered, defer: false)
        let existingContent = try XCTUnwrap(existing.contentView)
        defer { existing.orderOut(nil) }
        for cancel in [false, true] {
        weak var providerInput: NSView?
        var receivedExpectedError = false
        let operation = Task { @MainActor in
            try await withNativeApplicationEnvironment {
                try await withFixture { fixture in
                    try await fixture.withApplication { _ in
                        let onboarding = try XCTUnwrap(NSApp.windows.first {
                            $0.isVisible && $0.contentViewController is NSHostingController<OnboardingContainerView>
                        })
                        try await openProviderFromOnboarding(onboarding)
                        let management = try XCTUnwrap(NSApp.windows.first {
                            $0.isVisible && $0.title == "VLMSnapper" && $0 !== onboarding
                        })
                        let field = try await editableSecureField(in: management)
                        providerInput = try XCTUnwrap(field.superview)
                        if cancel {
                            await fixture.http.pause()
                            XCTAssertTrue(management.makeFirstResponder(field))
                            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
                            editor.insertText("fixture-cancel-key", replacementRange: editor.selectedRange())
                            pumpNativeEvents(management)
                            try clickValidate(below: field, in: management)
                            try await eventually { await fixture.http.requests.count == 1 }
                            withUnsafeCurrentTask { $0?.cancel() }
                            throw CancellationError()
                        }
                        throw FixtureError.unexpectedOperation
                    }
                }
            }
        }
        do {
            try await operation.value
        } catch is CancellationError {
            receivedExpectedError = cancel
        } catch FixtureError.unexpectedOperation {
            receivedExpectedError = !cancel
        }
        XCTAssertTrue(receivedExpectedError)
        XCTAssertNil(providerInput, "Error propagation must follow native view cleanup")
        XCTAssertTrue(existing.contentView === existingContent)
        }
    }

    func testValidationCompletesWhileManagementRemainsClosed() async throws {
        weak var providerInput: NSView?
        do {
            try await withNativeApplicationEnvironment {
                try await withFixture { fixture in
                    await fixture.http.pause()
                    try await fixture.withApplication { _ in
                        let onboarding = try XCTUnwrap(NSApp.windows.first {
                            $0.isVisible && $0.contentViewController is NSHostingController<OnboardingContainerView>
                        })
                        try await openProviderFromOnboarding(onboarding)
                        let management = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == "VLMSnapper" && $0 !== onboarding })
                        let field = try await editableSecureField(in: management)
                        XCTAssertTrue(management.makeFirstResponder(field))
                        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
                        editor.insertText("fixture-closed-key", replacementRange: editor.selectedRange())
                        pumpNativeEvents(management)
                        try clickValidate(below: field, in: management)
                        try await eventually { await fixture.http.requests.count == 1 }
                        management.performClose(nil)
                        try await eventually { onboarding.isVisible && !management.isVisible }
                        XCTAssertFalse(try renderedText(in: onboarding).contains("Choose a model"))
                        await fixture.http.release()
                        try await eventually {
                            pumpWindowActivationEvents()
                            return try renderedText(in: onboarding).contains("Choose a model")
                        }
                        XCTAssertTrue(onboarding.isVisible)
                        XCTAssertFalse(management.isVisible)
                        try await openProviderFromOnboarding(onboarding)
                        let reopened = try await editableSecureField(in: management)
                        providerInput = try XCTUnwrap(reopened.superview)
                        XCTAssertEqual(reopened.stringValue, "fixture-closed-key")
                        let requests = await fixture.http.requests
                        XCTAssertEqual(requests.count, 1)
                    }
                }
            }
            try await eventually {
                pumpWindowActivationEvents()
                return providerInput == nil
            }
        } catch {
            XCTFail("Closed-window validation did not complete: \(error)")
        }
    }

    func testNativeMainMenuPasteValidatesThroughRealKeyWindow() async throws {
        let trace = NativeWaitTrace(name: "paste")
        defer { trace.emit() }
        weak var providerInput: NSView?
        do {
            try await withNativeApplicationEnvironment {
                try await withFixture { fixture in
                    try await fixture.withApplication { _ in
                        let onboarding = try XCTUnwrap(NSApp.windows.first {
                            $0.isVisible && $0.contentViewController is NSHostingController<OnboardingContainerView>
                        })
                        try await openProviderFromOnboarding(onboarding)
                        let management = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == "VLMSnapper" && $0 !== onboarding })
                        let field = try await editableSecureField(in: management)
                        trace.record("before-activation", window: management)
                        providerInput = try XCTUnwrap(field.superview)
                        management.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                        try await eventually {
                            pumpWindowActivationEvents()
                            trace.record("key-window-wait", window: management)
                            return NSApp.keyWindow === management
                        }
                        trace.record("key-window-ready", window: management)
                        XCTAssertTrue(management.makeFirstResponder(field))
                        XCTAssertTrue(fixture.pasteboard.setString("fixture-menu-key\r\n", forType: .string))
                        let edit = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu)
                        let pasteIndex = edit.indexOfItem(withTitle: "Paste")
                        XCTAssertGreaterThanOrEqual(pasteIndex, 0)
                        edit.update()
                        XCTAssertTrue(try XCTUnwrap(edit.item(at: pasteIndex)).isEnabled)
                        edit.performActionForItem(at: pasteIndex)
                        trace.record("paste-dispatched", window: management)
                        try await eventually {
                            pumpNativeEvents(management)
                            return field.stringValue == "fixture-menu-key"
                        }
                        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
                        XCTAssertEqual(editor.selectedRange(), NSRange(location: 16, length: 0))
                        try clickValidate(below: field, in: management)
                        trace.record("validate-dispatched", window: management)
                        try await eventually { await fixture.credentials.credential(for: .deepSeek)?.apiKey == "fixture-menu-key" }
                        let requests = await fixture.http.requests
                        XCTAssertEqual(requests.count, 1)
                        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-menu-key")
                    }
                }
            }
            try await eventually {
                pumpWindowActivationEvents()
                return providerInput == nil
            }
        } catch {
            trace.record("failed")
            XCTFail("Main-menu Paste and validation did not complete: \(error)")
        }
    }
}
