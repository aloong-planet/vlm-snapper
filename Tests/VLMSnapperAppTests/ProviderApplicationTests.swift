import AppKit
import Foundation
import SQLite3
import SwiftUI
import Testing
import XCTest
import Vision
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// Programmatic native input and delegate routing, not physical keyboard,
// OS foregrounding, live-account or signed-app acceptance. Delegate tests
// mutate process-wide AppKit/localization state; run this suite separately.
// Only external adapters are replaced; the editor, sessions, coordinator,
// model-list parser, metadata files and SQLite use production implementations.
// Capture uses synthetic pixels and real native selection/toolbar/result events.
// Bilingual layout, physical shortcuts, unsaved-result dialogs and every
// failure/cancellation permutation remain separate acceptance work.
// The XCTest case below owns real key-window activation and main-menu Paste.
// It is still programmatic input, not installed-app physical Cmd+V acceptance.
// Closed-window completion is observed from the actual onboarding view render;
// this is not desktop capture or an occlusion/physical-focus check.
// CI and the local gate run the Paste and closed-window cases separately; the
// thrown-operation case runs only when invoked by name. Same-process repeats
// cover fixture teardown without relying on process exit to release the native
// view graph.
// Wait traces are diagnostic only: observation can affect scheduling, and a
// process abort before the deferred flush can lose the buffered transitions.
// Historical intermittent deadlines still need a failing, instrumented run.
// History retry tests exercise production callbacks and rebuild the model from disk.
// History retries remain inline; double clicking no longer opens a result window.
// Production callback tests do not claim installed-app physical Retry clicks.
// Display tests inject OS notifications and geometry snapshots; physical
// hot-plug, display sleep and multi-monitor focus require hardware acceptance.
// Pending-overlay tests hold the injected capturer, so they cannot show that the
// compositor leaves the pending overlay out of real frames (signed-app check), a
// second display whose freeze fails while another commits (two displays needed),
// a display connected while frames are pending (hot-plug during the freeze), the
// absence of a desktop flash between overlays (one main-thread call; check by
// screen recording), or every display invalidated before commit (modal failure
// alert blocks the run).
// Window-server hit testing is also out of reach: `sendEvent` skips it, so a click
// inside a clear pending selection reaching another app needs posted HID events
// with Accessibility trust (verified outside the suite, see the construction notes).
// Snap regions (v1-core::REQ-006): hover latency with many windows and the real window list of
// a signed sandboxed app are checked on the installed build, not here.
// The window-open animation of the overlay changes only composited frames, not the
// window frame, window-server bounds or layers: the overlay controller tests assert the
// window's animation behavior, and full first-frame coverage was checked by screen recording.
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

@Suite(.serialized)
@MainActor
struct ProviderApplicationTests {
    @Test(arguments: [0, 2, 5, 6])
    func recentMenuShowsAtMostFiveSavedRecords(count: Int) async throws {
        try await withFixture { fixture in
            let store = try SQLiteHistoryStore(databaseURL: fixture.root.appendingPathComponent("history.sqlite"))
            let titles = ["Oldest entry", "Meeting notes", "Release notes", "Travel plans", "Project summary", "Latest entry"]
            for title in titles.prefix(count) {
                let prepared = try await store.prepareExtraction(
                    screenshot: ManagedScreenshot(path: fixture.root.appendingPathComponent("missing.png").path, sha256: "fixture"),
                    selection: ProviderSelection(providerID: "deepseek", modelID: "fixture-model"))
                try await store.finish(operationID: prepared.operationID,
                    with: .succeeded(sourceMarkdown: title, translationMarkdown: nil))
            }
            try await fixture.withModel { model in
                let hosting = NSHostingView(rootView: model.menuView())
                hosting.appearance = NSAppearance(named: .aqua)
                hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 600)
                let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                defer { window.contentView = nil; window.close() }
                window.setContentSize(hosting.fittingSize)
                let text = try renderedText(in: window)
                let visibleTitles: [String]
                switch count {
                case 0: visibleTitles = []
                case 2: visibleTitles = ["Meeting notes", "Oldest entry"]
                case 5: visibleTitles = ["Project summary", "Travel plans", "Release notes", "Meeting notes", "Oldest entry"]
                default: visibleTitles = ["Latest entry", "Project summary", "Travel plans", "Release notes", "Meeting notes"]
                }
                for title in titles {
                    #expect(text.contains(title) == visibleTitles.contains(title), "Unexpected menu visibility for \(title): \(text)")
                }
                #expect(text.contains("Provider") && text.contains("Settings"), "Footer must remain visible")
                #expect(model.historyRecords.count == count, "The menu limit must not truncate stored history")
            }
        }
    }

    @Test
    func historyImageDoesNotReportFailureBeforeLoadingCompletes() async throws {
        try await withFixture { fixture in
            let store = try SQLiteHistoryStore(databaseURL: fixture.root.appendingPathComponent("history.sqlite"))
            let prepared = try await store.prepareOperation(
                screenshot: ManagedScreenshot(path: "/not-read-yet.png", sha256: "fixture"),
                selection: ProviderSelection(providerID: "deepseek", modelID: "fixture"), operation: .extractText)
            try await store.finish(operationID: prepared.operationID, with: .succeeded(sourceMarkdown: "Saved text remains readable", translationMarkdown: nil))
            let records = try await store.history(matching: HistoryQuery())
            VLMSnapperLocalization.configure(effectiveLanguage: .english)
            // No callback has completed a read. A nil image is not evidence of failure.
            let controller = ManagementCenterWindowController(records: records)
            let window = try #require(controller.window)
            defer { controller.close() }
            controller.show(destination: .history)
            let visible = try renderedText(in: window).lowercased()
            #expect(visible.contains("saved text remains readable"))
            #expect(!visible.contains("moved, deleted"))
            #expect(!visible.contains("loading"))
        }
    }

    @Test
    func historyImageRemainsVisibleWhileSameRecordReloads() async throws {
        try await withFixture { fixture in
            let screenshots = FileSystemScreenshotStore(rootDirectory: fixture.root.appendingPathComponent("Pictures"))
            let loader = ControlledHistoryImages(store: screenshots)
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let screenshot = try await screenshots.save(originalPNG: #require(bitmap.representation(using: .png, properties: [:])))
            let store = try SQLiteHistoryStore(databaseURL: fixture.root.appendingPathComponent("history.sqlite"))
            let record = try await store.prepareOperation(screenshot: screenshot,
                selection: ProviderSelection(providerID: "deepseek", modelID: "fixture"), operation: .extractText)
            try await store.finish(operationID: record.operationID, with: .succeeded(sourceMarkdown: "Original", translationMarkdown: nil))
            try await fixture.withModel(historyImageLoader: loader) { model in
                model.managementCallbacks().onSelectRecord(record.operationID)
                try await eventually { model.selectedHistoryImage != nil }
                await loader.pause()
                model.managementCallbacks().onSelectRecord(record.operationID)
                try await eventually { await loader.pendingCount == 1 }
                #expect(model.selectedHistoryImage != nil, "A same-record refresh must retain the validated image during IO")
                await loader.releaseAll()
                try await eventually { model.selectedHistoryImage != nil }
            }
        }
    }

    @Test
    func historyImageSwitchesIgnoreLateReadsAndRecoverAfterFailure() async throws {
        try await withFixture { fixture in
            let screenshots = FileSystemScreenshotStore(rootDirectory: fixture.root.appendingPathComponent("Pictures"))
            let loader = ControlledHistoryImages(store: screenshots)
            let store = try SQLiteHistoryStore(databaseURL: fixture.root.appendingPathComponent("history.sqlite"))
            var ids: [UUID] = [], images: [ManagedScreenshot] = [], pngs: [Data] = []
            for width in [4, 8] {
                let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 4,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                let image = try await screenshots.save(originalPNG: png)
                let record = try await store.prepareOperation(screenshot: image,
                    selection: ProviderSelection(providerID: "deepseek", modelID: "fixture"), operation: .extractText)
                try await store.finish(operationID: record.operationID, with: .succeeded(sourceMarkdown: "Saved text", translationMarkdown: nil))
                ids.append(record.operationID); images.append(image); pngs.append(png)
            }
            try await fixture.withModel(historyImageLoader: loader) { model in
                await loader.pause()
                model.managementCallbacks().onSelectRecord(ids[0])
                try await eventually { await loader.pendingCount == 1 }
                #expect(!model.selectedHistoryImageLoadFailed)
                model.managementCallbacks().onSelectRecord(ids[1])
                try await eventually { await loader.pendingCount == 2 }
                #expect(model.selectedHistoryImage == nil)
                model.managementCallbacks().onSelectRecord(ids[0])
                try await eventually { await loader.pendingCount == 3 }
                await loader.release(at: 2)
                try await eventually { model.selectedHistoryImage?.size.width == 4 }
                // The original A read now fails after the newer A read succeeded.
                try FileManager.default.removeItem(atPath: images[0].path)
                await loader.releaseAll()
                try await eventually { await loader.finishedCount == 3 }
                let deadline = ContinuousClock.now.advanced(by: .milliseconds(100))
                repeat {
                    #expect(model.selectedHistoryRecordID == ids[0])
                    #expect(model.selectedHistoryImage?.size.width == 4)
                    #expect(!model.selectedHistoryImageLoadFailed)
                    await Task.yield()
                } while ContinuousClock.now < deadline

                model.managementCallbacks().onSelectRecord(ids[0])
                try await eventually { model.selectedHistoryImageLoadFailed }
                #expect(model.selectedHistoryImage == nil)
                let controller = ManagementCenterWindowController(records: model.historyRecords,
                    selectedRecordID: ids[0], selectedImage: model.selectedHistoryImage,
                    selectedImageLoadFailed: model.selectedHistoryImageLoadFailed)
                defer { controller.close() }
                controller.show(destination: .history)
                let failedText = try renderedText(in: #require(controller.window)).lowercased()
                #expect(failedText.contains("moved, deleted"))
                #expect(failedText.contains("saved text"))

                try pngs[0].write(to: URL(fileURLWithPath: images[0].path))
                model.managementCallbacks().onSelectRecord(ids[0])
                try await eventually { model.selectedHistoryImage?.size.width == 4 }
                #expect(!model.selectedHistoryImageLoadFailed)
                model.managementCallbacks().onSelectRecord(ids[1])
                try await eventually { model.selectedHistoryImage?.size.width == 8 }
                #expect(model.selectedHistoryRecordID == ids[1])
            }
        }
    }

    @Test(arguments: [PersistedOperationKind.extract, .translate])
    func historyRetryUpdatesOriginalRecord(kind: PersistedOperationKind) async throws {
        try await withFixture { fixture in
            let screenshots = FileSystemScreenshotStore(rootDirectory: fixture.root.appendingPathComponent("Pictures"))
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let screenshot = try await screenshots.save(originalPNG: png)
            let store = try SQLiteHistoryStore(databaseURL: fixture.root.appendingPathComponent("history.sqlite"))
            let prepared = try await store.prepareOperation(screenshot: screenshot,
                selection: ProviderSelection(providerID: "deepseek", modelID: "old-model"),
                operation: kind == .extract ? .extractText : .translate(targetLanguage: "ja"))
            try await store.finish(operationID: prepared.operationID,
                with: .succeeded(sourceMarkdown: "Archived original",
                    translationMarkdown: kind == .translate ? "Archived translation" : nil))
            await fixture.http.allowImageRequests()
            try await fixture.withModel { model in
                let controls = model.providerSettingsConfiguration()
                model.credentialEditor.edit("fixture-history-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false, operation: controls.onValidate))
                try await eventually { model.providerSnapshot.phase == .selectingModel }
                controls.onSelectModel("fixture-vision")
                try await eventually { model.providerSnapshot.phase == .ready }
                try await eventually { model.historyRetry.allowsStart }
                model.managementCallbacks().onRetryRecord(prepared.operationID)
                model.managementCallbacks().onRetryRecord(prepared.operationID)
                try await eventually {
                    let count = await fixture.http.imageRequests.count
                    return !model.historyRetry.isRunning || count == 1
                }
                try #require(await fixture.http.imageRequests.count == 1, "Retry ended before HTTP: \(model.historyRetry.slot.attempt)")
                #expect(model.historyRetry.recordID == prepared.operationID)
                let progressWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
                progressWindow.isReleasedWhenClosed = false
                progressWindow.contentView = NSHostingView(rootView: ManagementCenterView(
                    destination: .history, records: model.historyRecords,
                    selectedRecordID: prepared.operationID, selectedImage: NSImage(data: png),
                    callbacks: model.managementCallbacks()))
                progressWindow.orderFront(nil)
                defer { progressWindow.close() }
                try await eventually { try renderedText(in: progressWindow).lowercased().contains("preparing") }
                let progressText = try renderedText(in: progressWindow).lowercased()
                #expect(progressText.contains("preparing"), "The pending request must remain visible")
                #expect(!progressText.split(separator: "\n").contains {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines) == "retry"
                }, "An active retry must not add a Retry heading above the original text")
                progressWindow.close()
                try await fixture.http.finishImage(source: "Retried result\n\nRetained historical paragraph.", translation: kind == .translate ? "Translated result" : nil)
                try await eventually { !model.historyRetry.isRunning }
                #expect(model.historyRetry.slot.attempt == .succeeded)
                #expect(model.historyRecords.count == 1)
                #expect(try await store.operation(id: prepared.operationID)?.sourceMarkdown == "Retried result\n\nRetained historical paragraph.")
                #expect(model.historyRecords.first { $0.id == prepared.operationID }?.operation.selection.modelID == "fixture-vision")
                #expect(await fixture.http.imageRequests.count == 1)
                #expect(model.historyRetry.slot.committedResult?.sourceMarkdown == "Retried result\n\nRetained historical paragraph.")
                if kind == .translate {
                    #expect(model.historyRecords.first { $0.id == prepared.operationID }?.operation.targetLanguage == "ja")
                    #expect(model.historyRetry.slot.committedResult?.translationMarkdown == "Translated result")
                    #expect(try await store.operation(id: prepared.operationID)?.segments?.first?.translation == "Translated result")
                }
                #expect(!NSApp.windows.contains { $0.isVisible && $0.windowController is ResultWorkspaceWindowController })
                let preview = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
                preview.isReleasedWhenClosed = false
                preview.contentView = NSHostingView(rootView: ManagementCenterView(
                    destination: .history, records: model.historyRecords,
                    selectedRecordID: prepared.operationID, selectedImage: NSImage(data: png),
                    callbacks: model.managementCallbacks()))
                preview.orderFront(nil)
                defer { preview.close() }
                let visibleResult = try renderedText(in: preview).lowercased()
                #expect(visibleResult.contains("retried result"), "The production detail must render the completed retry, not only store it")
                let visibleLines = visibleResult.split(separator: "\n").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                #expect(!visibleLines.contains("retry"), "A completed retry must not leave a redundant section heading")
                #expect(!visibleLines.contains("done"), "The completed detail must not leave a separate success status")
                if kind == .translate { #expect(visibleResult.contains("translated result")) }
                preview.close()
                await fixture.http.pause()
                controls.onRefresh()
                try await eventually { model.providerSnapshot.refreshingProvider == .deepSeek }
                model.managementCallbacks().onRetryRecord(prepared.operationID)
                try await eventually { !model.historyRetry.isRunning }
                #expect(model.historyRetry.slot.attempt == .failed(code: "operation_busy"))
                #expect(await fixture.http.imageRequests.count == 1)
                await fixture.http.release()
                try await eventually { model.historyRetry.allowsStart }

                // A truncated external response fails inline, without overwriting the archived result.
                model.managementCallbacks().onRetryRecord(prepared.operationID)
                try await eventually { await fixture.http.imageRequests.count == 2 }
                await fixture.http.release()
                try await eventually { !model.historyRetry.isRunning }
                guard case .failed = model.historyRetry.slot.attempt else {
                    Issue.record("An incomplete response must fail: \(model.historyRetry.slot.attempt)")
                    return
                }
                #expect(model.historyRecords.count == 1)
                #expect(try await store.operation(id: prepared.operationID)?.sourceMarkdown == "Retried result\n\nRetained historical paragraph.")
                preview.contentView = NSHostingView(rootView: ManagementCenterView(
                    destination: .history, records: model.historyRecords,
                    selectedRecordID: prepared.operationID, selectedImage: NSImage(data: png),
                    callbacks: model.managementCallbacks()))
                preview.orderFront(nil)
                #expect(try renderedText(in: preview).lowercased().contains("retained historical paragraph"),
                    "A failed retry must keep the previous body readable, not only the row or title")
                preview.close()

                // Inject an actual SQLite write error only at successful completion.
                #expect(model.historyRetry.slot.committedResult?.sourceMarkdown == "Retried result\n\nRetained historical paragraph.",
                    "A failed history retry must retain the last committed text in the live session")
                var database: OpaquePointer?
                try #require(sqlite3_open(fixture.root.appendingPathComponent("history.sqlite").path, &database) == SQLITE_OK)
                defer { sqlite3_close(database) }
                try #require(sqlite3_exec(database, "CREATE TRIGGER retry_write_failure BEFORE UPDATE ON operations WHEN NEW.status = 'succeeded' BEGIN SELECT RAISE(ABORT, 'fixture write failure'); END", nil, nil, nil) == SQLITE_OK)
                model.managementCallbacks().onRetryRecord(prepared.operationID)
                try await eventually { await fixture.http.imageRequests.count == 3 }
                try await fixture.http.finishImage(source: "Unsaved result", translation: kind == .translate ? "Unsaved translation" : nil)
                try await eventually { !model.historyRetry.isRunning }
                #expect(model.historyRetry.slot.attempt == .resultPersistenceFailed)
                #expect(model.historyRetry.slot.unsavedResult?.sourceMarkdown == "Unsaved result")
                if kind == .translate {
                    #expect(model.historyRetry.slot.unsavedResult?.segments?.first?.translation == "Unsaved translation")
                    #expect(try await store.operation(id: prepared.operationID)?.segments?.first?.translation == "Translated result")
                }
                #expect(!model.historyRetry.allowsStart)
                model.managementCallbacks().onRetryRecord(prepared.operationID)
                #expect(!model.historyRetry.isRunning)
                var deletionResolved = false
                // Keep a temporary DB backup only for teardown if the negative case deletes recovery data.
                try #require(sqlite3_exec(database, "CREATE TEMP TABLE retry_cleanup_backup AS SELECT * FROM operations", nil, nil, nil) == SQLITE_OK)
                let previousObserver = model.onSnapshotChange
                model.onSnapshotChange = { deletionResolved = true; previousObserver?() }
                model.managementCallbacks().onClearHistory(true)
                try await eventually { deletionResolved }
                model.onSnapshotChange = previousObserver
                try #require(sqlite3_exec(database, "DROP TRIGGER retry_write_failure", nil, nil, nil) == SQLITE_OK)
                model.managementCallbacks().onRetryHistorySave()
                try await eventually { !model.historyRetry.isRunning }
                #expect(model.historyRetry.slot.attempt == .succeeded)
                #expect(model.historyRetry.slot.unsavedResult == nil)
                #expect(model.historyRecords.contains { $0.operation.sourceMarkdown == "Unsaved result" })
                #expect(model.historyRecords.contains { $0.id == prepared.operationID }, "Keep the inline recovery entry reachable until its result is saved")
                #expect(await fixture.http.imageRequests.count == 3)
                if model.historyRetry.slot.unsavedResult != nil {
                    // Assertions above already recorded the failure. Restore only the isolated fixture,
                    // so model termination does not open an unsaved-result modal during a red run.
                    try #require(sqlite3_exec(database, "INSERT OR IGNORE INTO operations SELECT * FROM retry_cleanup_backup", nil, nil, nil) == SQLITE_OK)
                    model.managementCallbacks().onRetryHistorySave()
                    try await eventually { !model.historyRetry.isRunning }
                }
                // A real file replacement must be rejected even after a previously valid preview.
                try Data("replaced file".utf8).write(to: URL(fileURLWithPath: screenshot.path))
                model.managementCallbacks().onRetryRecord(prepared.operationID)
                try await eventually { !model.historyRetry.isRunning }
                #expect(model.historyRetry.slot.attempt == .failed(code: "history_screenshot_unavailable"))
                #expect(await fixture.http.imageRequests.count == 3)
                #expect(model.historyRecords.count == 1)
                #expect(try await store.operation(id: prepared.operationID)?.sourceMarkdown == "Unsaved result")
            }
            try await fixture.withModel { reopened in
                try await eventually { reopened.historyRecords.count == 1 }
                #expect(reopened.historyRecords.first?.id == prepared.operationID)
                #expect(reopened.historyRecords.first?.operation.sourceMarkdown == "Unsaved result")
                if kind == .translate {
                    #expect(reopened.historyRecords.first?.operation.segments?.first?.translation == "Unsaved translation")
                }
                #expect(await fixture.http.imageRequests.count == 3, "Rebuilding the application never restarts history requests")
            }
        }
    }

    @Test
    func historyRetrySurvivesWindowChangesAndRejectsLateDeletion() async throws {
        try await withFixture { fixture in
            let screenshots = FileSystemScreenshotStore(rootDirectory: fixture.root.appendingPathComponent("Pictures"))
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let screenshot = try await screenshots.save(originalPNG: png)
            let tenDaysAgo = Date().addingTimeInterval(-10 * 86_400)
            let store = try SQLiteHistoryStore(databaseURL: fixture.root.appendingPathComponent("history.sqlite"),
                now: { tenDaysAgo })
            var identifiers: [UUID] = []
            for text in ["Original retry target", "Unrelated record"] {
                let prepared = try await store.prepareExtraction(screenshot: screenshot,
                    selection: ProviderSelection(providerID: "deepseek", modelID: "archived-model"))
                try await store.finish(operationID: prepared.operationID,
                    with: .succeeded(sourceMarkdown: text, translationMarkdown: nil))
                identifiers.append(prepared.operationID)
            }
            let target = identifiers[0], other = identifiers[1]
            await fixture.http.allowImageRequests()
            try await fixture.withModel { model in
                let controls = model.providerSettingsConfiguration()
                model.credentialEditor.edit("fixture-window-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false, operation: controls.onValidate))
                try await eventually { model.providerSnapshot.phase == .selectingModel }
                controls.onSelectModel("fixture-vision")
                try await eventually { model.historyRetry.allowsStart }
                let callbacks = model.managementCallbacks()
                callbacks.onRetentionChange(.sevenDays)
                try await eventually { model.settings.retentionShorteningRecordCount == 2 }
                var database: OpaquePointer?
                try #require(sqlite3_open(fixture.root.appendingPathComponent("history.sqlite").path, &database) == SQLITE_OK)
                defer { sqlite3_close(database) }
                try #require(sqlite3_exec(database, "CREATE TEMP TABLE late_cleanup_backup AS SELECT * FROM operations", nil, nil, nil) == SQLITE_OK)
                let controller = ManagementCenterWindowController(records: model.historyRecords,
                    selectedRecordID: target, callbacks: callbacks)
                let window = try #require(controller.window)
                defer { window.close(); model.onSnapshotChange = nil }
                var publications = 0
                model.onSnapshotChange = {
                    publications += 1
                    controller.update(records: model.historyRecords,
                        selectedRecordID: model.selectedHistoryRecordID,
                        selectedImage: model.selectedHistoryImage, cleanupFailureCount: model.cleanupFailureCount,
                        retention: model.retention, settings: model.settings, providerSettings: nil)
                }
                controller.show(destination: .history)
                callbacks.onSelectRecord(target)
                try await eventually { model.selectedHistoryRecordID == target && model.selectedHistoryImage != nil }
                // This callback represents confirmation of a delete dialog opened before Retry.
                let confirmOldDeletion = { callbacks.onDelete(target) }
                callbacks.onRetryRecord(target)
                try await eventually { await fixture.http.imageRequests.count == 1 }
                controller.hideForCapture()
                #expect(!window.isVisible)
                #expect(model.historyRetry.isRunning)
                controller.show(destination: .history)
                #expect(window.isVisible)
                #expect(model.historyRetry.recordID == target)
                callbacks.onSelectRecord(other)
                try await eventually { model.selectedHistoryRecordID == other && model.selectedHistoryImage != nil }
                let beforeDeletion = publications
                confirmOldDeletion()
                try await eventually { publications > beforeDeletion }
                #expect(try await store.history(matching: HistoryQuery()).count == 2)
                #expect(try await store.operation(id: target)?.sourceMarkdown == "Original retry target")
                let beforeCleanup = publications
                callbacks.onConfirmRetentionShortening()
                try await eventually { publications > beforeCleanup }
                let remaining = try await store.history(matching: HistoryQuery())
                #expect(remaining.count == 2, "A late retention confirmation must not delete an active retry target")
                // Recover only this isolated fixture after a red assertion, before completing HTTP.
                if remaining.count != 2 {
                    try #require(sqlite3_exec(database, "INSERT OR IGNORE INTO operations SELECT * FROM late_cleanup_backup", nil, nil, nil) == SQLITE_OK)
                    try FileManager.default.createDirectory(at: URL(fileURLWithPath: screenshot.path).deletingLastPathComponent(), withIntermediateDirectories: true)
                    try png.write(to: URL(fileURLWithPath: screenshot.path))
                }
                callbacks.onCancelRetentionShortening()
                try await eventually { model.settings.retentionShorteningRecordCount == nil }
                try await fixture.http.finishImage(source: "Completed while viewing another record")
                try await eventually { !model.historyRetry.isRunning }
                #expect(model.selectedHistoryRecordID == other)
                #expect(try await store.operation(id: other)?.sourceMarkdown == "Unrelated record")
                #expect(try await store.operation(id: target)?.sourceMarkdown == "Completed while viewing another record")
                #expect(model.historyRecords.count == 2)
                #expect(!NSApp.windows.contains { $0.isVisible && $0.windowController is ResultWorkspaceWindowController })

                callbacks.onSelectRecord(target)
                try await eventually { model.selectedHistoryRecordID == target }
                callbacks.onRetryRecord(target)
                try await eventually { await fixture.http.imageRequests.count == 2 }
                window.performClose(nil)
                #expect(!window.isVisible)
                #expect(model.historyRetry.isRunning)
                try await fixture.http.finishImage(source: "Completed while history was closed")
                try await eventually { !model.historyRetry.isRunning }
                #expect(!window.isVisible, "Completion must not reopen or activate the management window")
                controller.show(destination: .history)
                #expect(try renderedText(in: window).lowercased().contains("completed while history was closed"))
                #expect(model.historyRetry.recordID == target)
                #expect(model.historyRecords.count == 2)
                #expect(await fixture.http.imageRequests.count == 2)
                // Protection ends after successful persistence; the same public delete now succeeds.
                callbacks.onDelete(other)
                try await eventually { model.historyRecords.count == 1 }
                #expect(model.historyRecords.first?.id == target)
                #expect(try await store.operation(id: target)?.sourceMarkdown == "Completed while history was closed")
                callbacks.onRetentionChange(.sevenDays)
                try await eventually { model.settings.retentionShorteningRecordCount != nil }
                callbacks.onConfirmRetentionShortening()
                try await eventually { model.settings.retentionShorteningRecordCount == nil }
                #expect(try await store.history(matching: HistoryQuery()).isEmpty)
            }
        }
    }

    @Test
    func modelRefreshPublishesProgressAndFailureWithoutChangingCredentialState() async throws {
        try await withFixture { fixture in
            try await fixture.withModel { model in
                let controls = model.providerSettingsConfiguration()
                model.credentialEditor.edit("fixture-refresh-key")
                #expect(model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: controls.onValidate
                ))
                try await eventually { model.providerSnapshot.phase == .selectingModel }
                controls.onSelectModel("fixture-vision")
                try await eventually { model.providerSnapshot.phase == .ready }
                await fixture.http.pause()
                await fixture.http.respond(with: 503)
                controls.onRefresh()
                try await eventually { model.providerSnapshot.refreshingProvider == .deepSeek }
                #expect(model.providerSnapshot.phase == .ready)
                #expect(model.providerSnapshot.blocksConfigurationChanges)
                #expect(!model.credentialEditor.isSubmitting)
                #expect(model.providerSnapshot.availableModelIDs == ["fixture-vision"])
                try await eventually { await fixture.http.requests.count == 2 }
                await fixture.http.release()
                try await eventually {
                    model.providerSnapshot.refreshingProvider == nil
                        && model.providerSnapshot.modelRefreshFailure == .unavailable
                }
                #expect(model.providerSnapshot.failure == nil)
                #expect(model.providerSnapshot.phase == .ready)
                #expect(model.providerSnapshot.blocksConfigurationChanges == false)
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
                #expect(model.credentialEditor.value == "fixture-refresh-key")
                #expect(await fixture.http.requests.count == 2)
                await fixture.http.respond(with: 200)
                controls.onRefresh()
                try await eventually {
                    let requestCount = await fixture.http.requests.count
                    return model.providerSnapshot.refreshingProvider == nil
                        && model.providerSnapshot.modelRefreshFailure == nil
                        && requestCount == 3
                }
                #expect(model.providerSnapshot.selectedModelID == "fixture-vision")
            }
        }
    }

    @Test
    func nativeValidateSurvivesCloseAndReopenWhileResponseIsPending() async throws {
        try await withFixture { fixture in
            await fixture.http.pause()
            try await fixture.withApplication { _ in
                let onboarding = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentViewController is NSHostingController<OnboardingContainerView>
                })
                try await openProviderFromOnboarding(onboarding)
                let management = try #require(NSApp.windows.first { $0.isVisible && $0.title == "VLMSnapper" && $0 !== onboarding })
                let field = try await editableSecureField(in: management)
                #expect(management.makeFirstResponder(field))
                let editor = try #require(field.currentEditor() as? NSTextView)
                editor.insertText("fixture-window-key", replacementRange: editor.selectedRange())
                try await eventually {
                    pumpNativeEvents(management)
                    return field.stringValue == "fixture-window-key"
                }
                #expect(editor.selectedRange() == NSRange(location: 18, length: 0))
                // Locate the native field, then click the action immediately
                // beneath its trailing edge in the confirmed Provider layout.
                try clickValidate(below: field, in: management)
                try await eventually { await fixture.http.requests.count == 1 }
                #expect(await fixture.http.requests.first?.value(forHTTPHeaderField: "Authorization")
                    == "Bearer fixture-window-key")
                management.performClose(nil)
                try await eventually { onboarding.isVisible && !management.isVisible }
                #expect(await fixture.credentials.credential(for: .deepSeek) == nil)
                try await openProviderFromOnboarding(onboarding)
                try await eventually {
                    pumpNativeEvents(management)
                    return management.contentView.map {
                        descendants($0).compactMap { $0 as? NSSecureTextField }.contains {
                            $0.stringValue == "fixture-window-key" && !$0.isEditable
                        }
                    } == true
                }
                #expect(await fixture.http.requests.count == 1)
                #expect(await fixture.credentials.credential(for: .deepSeek) == nil)
                await fixture.http.release()
                let reopenedField = try await editableSecureField(in: management)
                #expect(reopenedField.stringValue == "fixture-window-key")
                try await eventually {
                    pumpNativeEvents(management)
                    return management.contentView.map {
                        descendants($0).compactMap { $0 as? NSPopUpButton }.contains { $0.itemTitles.contains("fixture-vision") }
                    } == true
                }
                #expect(await fixture.http.requests.count == 1)
                #expect(!onboarding.isVisible)
                #expect(management.isVisible)
            }
            try await fixture.withModel { model in
                #expect(model.credentialEditor.value == "fixture-window-key")
                #expect(model.providerReadiness == .pendingModel(.deepSeek))
                #expect(await fixture.http.requests.count == 1)
            }
        }
    }

    @Test
    func nativeCaptureAndRerunPreserveHistoryWhileProviderValidationIsExclusive() async throws {
        let trace = NativeWaitTrace(name: "capture")
        defer { trace.emit() }
        try await withFixture { fixture in
            fixture.permissionGranted = true
            await fixture.capture.provide(try syntheticDisplay())
            await fixture.http.allowImageRequests()
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-image-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                try await eventually {
                    model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let overlay = try #require(try mainScreenOverlay())
                pumpNativeEvents(overlay)
                trace.record("overlay-ready", window: overlay)
                try drag(overlay, from: NSPoint(x: 100, y: 200), to: NSPoint(x: 300, y: 300), trace: trace)
                try await eventually {
                    trace.record("toolbar-wait", window: overlay)
                    return NSApp.windows.contains { $0.isVisible && $0.contentView is NSHostingView<CaptureOperationToolbar> }
                }
                trace.record("toolbar-ready")
                let toolbar = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentView is NSHostingView<CaptureOperationToolbar>
                })
                // While the selection can still be adjusted, displays stay monitored (v1-core::REQ-007/AC-07);
                // an unchanged geometry leaves the selection and its toolbar alone.
                let selectingReads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                try await eventually { fixture.displayReads > selectingReads }
                #expect(toolbar.isVisible)
                try await eventually { model.providerSnapshot.activity == .capture }
                model.credentialEditor.edit("fixture-during-selection")
                let selectionBlocked = model.providerSettingsConfiguration()
                #expect(!model.credentialEditor.submit(for: .deepSeek,
                    isReadOnly: selectionBlocked.snapshot.blocksConfigurationChanges,
                    operation: selectionBlocked.onValidate))
                #expect(await fixture.http.requests.count == 1)
                pumpNativeEvents(toolbar)
                // Center of the first operation button in the production toolbar.
                let toolbarContent = try #require(toolbar.contentView)
                try click(toolbar, at: NSPoint(x: 40, y: toolbarContent.bounds.midY))
                try await eventually { await fixture.http.imageRequests.count == 1 }
                // Once an operation starts the capture's display monitoring is released (v1-core::REQ-001/AC-07).
                let operationReads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                fixture.workspaceNotifications.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
                #expect(fixture.displayReads == operationReads)
                try await eventually { model.providerSnapshot.blocksConfigurationChanges }
                model.credentialEditor.edit("fixture-during-image")
                let blocked = model.providerSettingsConfiguration()
                #expect(!model.credentialEditor.submit(for: .deepSeek,
                    isReadOnly: blocked.snapshot.blocksConfigurationChanges, operation: blocked.onValidate))
                #expect(await fixture.http.requests.count == 1)
                #expect(model.credentialEditor.value == "fixture-during-image")
                try await fixture.http.finishImage(source: "First result")
                try await eventually {
                    model.historyRecords.count == 1 && !model.providerSnapshot.blocksConfigurationChanges
                }
                let originalID = try #require(model.historyRecords.first?.id)
                #expect(model.historyRecords.first?.operation.sourceMarkdown == "First result")
                let originalHistory = model.historyRecords
                let result = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentViewController is NSHostingController<ResultWorkspaceView>
                })
                await fixture.http.pause()
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { await fixture.http.requests.count == 2 }
                try await eventually { model.providerSnapshot.activity == .credential(.deepSeek) }
                pumpNativeEvents(result)
                try clickRerun(result)
                #expect(await fixture.http.imageRequests.count == 1)
                #expect(model.historyRecords == originalHistory)
                await fixture.http.release()
                try await eventually {
                    pumpNativeEvents(result)
                    return !model.credentialEditor.isSubmitting && model.providerSnapshot.activity == nil
                }
                #expect(await fixture.http.imageRequests.count == 1)
                #expect(model.historyRecords == originalHistory)
                pumpNativeEvents(result)
                try clickRerun(result)
                try await eventually { await fixture.http.imageRequests.count == 2 }
                #expect(model.historyRecords == originalHistory)

                // External credential truth after an interrupted publication:
                // a saved key with no metadata. Opening that card must wait
                // for this in-flight rerun before starting recovery HTTP.
                await fixture.credentials.replaceCredential(
                    ProviderCredential(generation: UUID(), apiKey: "fixture-recovery-key"), for: .openAI
                )
                await fixture.http.pause()
                model.providerSettingsConfiguration().onSelectProvider(.openAI)
                try await eventually {
                    model.providerSnapshot.selectedProvider == .openAI && model.credentialEditor.isLoading
                }
                #expect(model.providerSnapshot.activity == .modelRequest)
                #expect(await fixture.http.requests.count == 2)
                #expect(model.historyRecords == originalHistory)
                try await fixture.http.finishImage(source: "Replacement result")
                try await eventually { model.historyRecords.first?.operation.sourceMarkdown == "Replacement result" }
                #expect(model.historyRecords.count == 1)
                #expect(model.historyRecords.first?.id == originalID)
                try await eventually {
                    await fixture.http.requests.count == 3 && model.providerSnapshot.phase == .recovering
                }
                #expect(await fixture.http.requests.last?.url?.host == "api.openai.com")
                let recoveredHistory = model.historyRecords
                var recoveryNavigations = 0
                model.onNavigate = { if $0 == .providerSettings { recoveryNavigations += 1 } }
                try fixture.shortcuts.fire()
                try await eventually { recoveryNavigations == 1 }
                #expect(await fixture.capture.requests == 1)
                pumpNativeEvents(result)
                try clickRerun(result)
                #expect(await fixture.http.imageRequests.count == 2)
                #expect(model.historyRecords == recoveredHistory)
                await fixture.http.release()
                try await eventually {
                    !model.credentialEditor.isLoading && model.providerSnapshot.activity == nil
                        && model.providerSnapshot.availableModelIDs == ["fixture-vision"]
                }
                #expect(model.credentialEditor.value == "fixture-recovery-key")
                #expect(await fixture.http.imageRequests.count == 2)
                #expect(model.historyRecords == recoveredHistory)
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
            }
        }
    }

    @Test(arguments: DisplayChange.allCases)
    func displayChangesCancelSelectionBeforeMouseUp(change: DisplayChange) async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-display-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                try await eventually {
                    model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let overlay = try #require(try mainScreenOverlay())
                // The selection and its display subscription begin with the frozen frame.
                try await eventually { try overlayShowsFrozenFrame(overlay) }
                let reads = fixture.displayReads
                try await eventually { model.providerSnapshot.activity == .capture }
                fixture.displayGeometries = [display.geometry, changedGeometry(display.geometry, id: UInt32.max)]
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                #expect(fixture.displayReads == reads + 1)
                #expect(overlay.isVisible)
                #expect(NSApp.windows.filter { $0.isVisible && $0.level == .screenSaver }.count == 1)
                if change == .sleep {
                    fixture.workspaceNotifications.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
                } else {
                    fixture.displayGeometries = change == .disconnect ? [] : [changedGeometry(
                        display.geometry, scale: change == .scale, rotate: change == .rotate, move: change == .move
                    )]
                    fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                }
                // Invalidation removes the native hit target synchronously,
                // without waiting for a mouse-up or an actor completion.
                #expect(!overlay.isVisible)
                try await eventually { !overlay.isVisible && model.providerSnapshot.activity == nil }
                #expect(overlay.contentView == nil)
                #expect(model.historyRecords.isEmpty)
                #expect(await fixture.http.imageRequests.isEmpty)
                let stoppedReads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                #expect(fixture.displayReads == stoppedReads)
            }
        }
    }

    @Test
    func replacementAndEscapeRetireDisplaySubscriptions() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-display-lifecycle-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                try await eventually {
                    model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }
                var previous: NSWindow?
                for _ in 0..<2 {
                    try fixture.shortcuts.fire()
                    try await eventually {
                        model.providerSnapshot.activity == .capture && NSApp.windows.contains {
                            $0.isVisible && $0.level == .screenSaver && $0 !== previous
                        }
                    }
                    let overlay = try #require(try mainScreenOverlay())
                    // Retirement and display subscriptions follow the frozen frame.
                    try await eventually { try overlayShowsFrozenFrame(overlay) }
                    if let previous {
                        #expect(!previous.isVisible)
                        #expect(previous.contentView == nil)
                    }
                    let reads = fixture.displayReads
                    fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                    #expect(fixture.displayReads == reads + 1)
                    #expect(overlay.isVisible)
                    previous = overlay
                }
                let overlay = try #require(previous)
                pumpNativeEvents(overlay)
                overlay.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: overlay.windowNumber, context: nil, characters: "\u{1b}",
                    charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
                try await eventually { !overlay.isVisible && model.providerSnapshot.activity == nil }
                #expect(overlay.contentView == nil)
                let reads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                #expect(fixture.displayReads == reads)
                try fixture.shortcuts.fire()
                try await eventually {
                    model.providerSnapshot.activity == .capture && NSApp.windows.contains {
                        $0.isVisible && $0.level == .screenSaver
                    }
                }
                #expect(await model.prepareForTermination())
                let terminatedReads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                #expect(fixture.displayReads == terminatedReads)
                #expect(!NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver })
                #expect(model.historyRecords.isEmpty)
            }
        }
    }

    @Test
    func overlayCoversDisplaysBeforeFreezeCompletes() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-overlay-key")
                var retiredSources = 0
                model.onRetireCaptureSources = { retiredSources += 1 }
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                // The capturer is still suspended, so no frozen frame exists yet.
                try await eventually {
                    try await fixture.capture.requests == 1 && mainScreenOverlay() != nil
                }
                let overlay = try #require(try mainScreenOverlay())
                let everyScreenCovered = NSScreen.screens.allSatisfy { screen in
                    NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver && $0.frame == screen.frame }
                }
                #expect(everyScreenCovered)
                #expect(try !overlayShowsFrozenFrame(overlay))
                // Menu, management center and onboarding stay until the frame is shown.
                #expect(retiredSources == 0)
                await fixture.capture.release()
                try await eventually { try overlayShowsFrozenFrame(overlay) }
                #expect(overlay.isVisible)
                #expect(try mainScreenOverlay() === overlay)
                #expect(retiredSources == 1)
            }
        }
    }

    @Test
    func selectionDraggedWhileFreezingCompletesWithFrozenFrames() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-selection-key")
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let overlay = try #require(try mainScreenOverlay())
                pumpNativeEvents(overlay)
                try drag(overlay, from: NSPoint(x: 100, y: 200), to: NSPoint(x: 300, y: 300))
                #expect(try !overlayShowsFrozenFrame(overlay))
                #expect(captureToolbar() == nil)
                await fixture.capture.release()
                try await eventually { captureToolbar() != nil }
                #expect(try overlayShowsFrozenFrame(overlay))
            }
        }
    }

    @Test
    func escapeWhileFreezingExitsCapture() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-escape-key")
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let overlay = try #require(try mainScreenOverlay())
                pumpNativeEvents(overlay)
                // The keyboard belongs to the pending overlay, so the application routes Esc to it.
                #expect(overlay.isKeyWindow)
                try pressEscapeThroughApplication()
                try await eventually { !captureOverlayIsVisible() }
                // The freeze finishes after the user left; its frames must not reopen the selection.
                await fixture.capture.release()
                try await eventually { model.providerSnapshot.activity == nil }
                #expect(!captureOverlayIsVisible())
                #expect(captureToolbar() == nil)
                #expect(model.historyRecords.isEmpty)
                #expect(await fixture.http.imageRequests.isEmpty)
            }
        }
    }

    @Test
    func terminationWhileFreezingWithdrawsOverlay() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-termination-key")
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                // Frames are still held, so preparation must not wait for the freeze.
                #expect(await model.prepareForTermination())
                #expect(!captureOverlayIsVisible())
                #expect(model.historyRecords.isEmpty)
            }
        }
    }

    @Test
    func failedFreezeRestoresPreviousSelection() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-failure-key")
                var retiredSources = 0
                model.onRetireCaptureSources = { retiredSources += 1 }
                let (previous, toolbar) = try await completeSelection(fixture)
                #expect(retiredSources == 1)

                await fixture.capture.provide(nil)
                await fixture.capture.allowSuspendedCapture()
                var onboardingRequests = 0
                model.onShowOnboarding = { onboardingRequests += 1 }
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 2 && mainScreenOverlay() != nil
                }
                let pending = try #require(try mainScreenOverlay())
                #expect(pending !== previous)
                #expect(!previous.isVisible)
                #expect(!toolbar.isVisible)
                await fixture.capture.release()
                try await eventually { onboardingRequests == 1 }
                #expect(!pending.isVisible)
                #expect(previous.isVisible)
                #expect(try overlayShowsFrozenFrame(previous))
                #expect(toolbar.isVisible)
                #expect(model.providerSnapshot.activity == .capture)
                // A failed capture retires no source interface.
                #expect(retiredSources == 1)
            }
        }
    }

    @Test
    func escapeWhileReplacingSelectionReleasesActivity() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-replacement-key")
                let (previous, toolbar) = try await completeSelection(fixture)

                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 2 && mainScreenOverlay() != nil
                }
                let pending = try #require(try mainScreenOverlay())
                #expect(pending !== previous)
                pumpNativeEvents(pending)
                try pressEscape(pending)
                try await eventually { !captureOverlayIsVisible() }
                #expect(!toolbar.isVisible)
                await fixture.capture.release()
                // One capture activity is shared by both selections; leaving must release it.
                try await eventually { model.providerSnapshot.activity == nil }
                #expect(!captureOverlayIsVisible())
                #expect(!toolbar.isVisible)
                #expect(model.historyRecords.isEmpty)
            }
        }
    }

    @Test
    func escapeWhileFreezingFromResultRestoresWorkspace() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            await fixture.http.allowImageRequests()
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-workspace-key")
                let (_, toolbar) = try await completeSelection(fixture)
                pumpNativeEvents(toolbar)
                // Center of the first operation button in the production toolbar.
                let toolbarContent = try #require(toolbar.contentView)
                try click(toolbar, at: NSPoint(x: 40, y: toolbarContent.bounds.midY))
                try await eventually { await fixture.http.imageRequests.count == 1 }
                try await fixture.http.finishImage(source: "First result")
                try await eventually {
                    model.historyRecords.count == 1 && !model.providerSnapshot.blocksConfigurationChanges
                }
                let result = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentViewController is NSHostingController<ResultWorkspaceView>
                })

                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 2 && mainScreenOverlay() != nil
                }
                let pending = try #require(try mainScreenOverlay())
                pumpNativeEvents(pending)
                try pressEscape(pending)
                try await eventually { !captureOverlayIsVisible() }
                await fixture.capture.release()
                try await eventually { model.providerSnapshot.activity == nil }
                #expect(result.isVisible)
                // A workspace still reserved for the abandoned capture refuses the next one.
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 3 && mainScreenOverlay() != nil
                }
            }
        }
    }

    @Test
    func selectionStartedBeforeFramesFinishesAfterThem() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-drag-key")
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let overlay = try #require(try mainScreenOverlay())
                pumpNativeEvents(overlay)
                try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 300), to: overlay)
                try sendMouse(.leftMouseDragged, at: NSPoint(x: 400, y: 400), to: overlay)
                await fixture.capture.release()
                try await eventually { try overlayShowsFrozenFrame(overlay) }
                #expect(captureToolbar() == nil)
                // Still dragging after the frame arrived: the rectangle's left edge moves to 150.
                try sendMouse(.leftMouseDragged, at: NSPoint(x: 150, y: 400), to: overlay)
                try sendMouse(.leftMouseUp, at: NSPoint(x: 150, y: 400), to: overlay)
                try await eventually { captureToolbar() != nil }
                let toolbar = try #require(captureToolbar())
                // The toolbar is left-aligned with the selection that mouse-up completed.
                #expect(abs(toolbar.frame.minX - (overlay.frame.minX + 150)) <= 1)
            }
        }
    }

    // v1-core::REQ-006: a click selects the snap region from the window list taken with the
    // freeze. The selection shows through the toolbar, which is left-aligned with it.
    @Test
    func clickOnWindowSelectsWholeWindow() async throws {
        try await withSnapFixture { fixture, screen, model in
            try fixture.shortcuts.fire()
            let overlay = try await frozenMainOverlay()
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 301, y: 251), to: overlay)
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            #expect(abs(toolbar.frame.minX - (screen.frame.minX + 200)) <= 1)
            #expect(toolbar.frame.maxY <= screen.frame.minY + 150)
        }
    }

    @Test
    func clickOnDesktopSelectsWholeDisplay() async throws {
        try await withSnapFixture { fixture, screen, model in
            try fixture.shortcuts.fire()
            let overlay = try await frozenMainOverlay()
            try sendMouse(.leftMouseDown, at: NSPoint(x: 60, y: 600), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 60, y: 600), to: overlay)
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            #expect(abs(toolbar.frame.minX - screen.visibleFrame.minX) <= 1)
        }
    }

    @Test
    func clickWhileFreezingSelectsWindowOnceFramesArrive() async throws {
        try await withSnapFixture { fixture, screen, model in
            await fixture.capture.holdFrames()
            try fixture.shortcuts.fire()
            try await eventually { try mainScreenOverlay() != nil }
            let overlay = try #require(try mainScreenOverlay())
            pumpNativeEvents(overlay)
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
            #expect(captureToolbar() == nil)
            await fixture.capture.release()
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            #expect(abs(toolbar.frame.minX - (screen.frame.minX + 200)) <= 1)
        }
    }

    @Test
    func clickWithoutWindowListSelectsNothingButDragStillWorks() async throws {
        try await withSnapFixture(windowList: false) { fixture, screen, model in
            try fixture.shortcuts.fire()
            let overlay = try await frozenMainOverlay()
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
            // Selections are handled in order: the toolbar that appears belongs to the drag.
            try drag(overlay, from: NSPoint(x: 120, y: 200), to: NSPoint(x: 260, y: 320))
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            #expect(abs(toolbar.frame.minX - (screen.frame.minX + 120)) <= 1)
        }
    }

    @Test
    func lateWindowListOfReplacedCaptureIsIgnored() async throws {
        try await withSnapFixture(windowList: false) { fixture, screen, model in
            let flipHeight = try #require(NSScreen.screens.first).frame.height
            func list(atLocalX x: CGFloat) -> CaptureWindowSnapshot {
                CaptureWindowSnapshot(windows: [CaptureWindowSnapshotEntry(
                    ownerProcessID: 4242, layer: 0, alpha: 1, isOnScreen: true,
                    bounds: CGRect(x: screen.frame.minX + x, y: flipHeight - (screen.frame.minY + 350), width: 300, height: 200)
                )], dockProcessID: nil)
            }
            // The first capture's list has a window at local x 200, the replacement's at x 700.
            await fixture.windows.provide(perCall: [list(atLocalX: 200), list(atLocalX: 700)])
            await fixture.windows.hold()
            let first = try await completeSelection(fixture).overlay
            await fixture.capture.holdFrames()
            try fixture.shortcuts.fire()
            try await eventually { try mainScreenOverlay().map { $0 !== first } ?? false }
            let overlay = try #require(try mainScreenOverlay())
            pumpNativeEvents(overlay)
            // The replacement's list arrives first, the first capture's afterwards. Click only
            // after both have been handed over, or the first list would resolve the click.
            await fixture.windows.release(newestFirst: true)
            try await eventually { await fixture.windows.returned == 2 }
            try await Task.sleep(for: .milliseconds(100))
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
            await fixture.capture.release()
            try await eventually { try overlayShowsFrozenFrame(overlay) && captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            // Local x 300 has no window in the replacement's list: the whole display is selected.
            #expect(abs(toolbar.frame.minX - screen.visibleFrame.minX) <= 1)
        }
    }

    @Test
    func windowListIsReadOnceAtTriggerWithoutOwnWindows() async throws {
        try await withSnapFixture(windowList: false) { fixture, screen, model in
            let flipHeight = try #require(NSScreen.screens.first).frame.height
            func entry(_ process: Int32, localX x: CGFloat, width: CGFloat) -> CaptureWindowSnapshotEntry {
                CaptureWindowSnapshotEntry(
                    ownerProcessID: process, layer: 0, alpha: 1, isOnScreen: true,
                    bounds: CGRect(x: screen.frame.minX + x, y: flipHeight - (screen.frame.minY + 350), width: width, height: 200)
                )
            }
            // First read: one of VLMSnapper's own windows in front at local x 280, a window at 200.
            // A second read before the click would move the toolbar to the display's edge; one after
            // it leaves the toolbar alone and is caught by the call count.
            let own = ProcessInfo.processInfo.processIdentifier
            await fixture.windows.provide(perCall: [
                CaptureWindowSnapshot(windows: [entry(own, localX: 280, width: 100), entry(4242, localX: 200, width: 300)], dockProcessID: nil),
                CaptureWindowSnapshot(windows: [], dockProcessID: nil),
            ])
            await fixture.capture.holdFrames()
            try fixture.shortcuts.fire()
            try await eventually { await fixture.windows.calls == 1 }
            try await eventually { try mainScreenOverlay() != nil }
            let overlay = try #require(try mainScreenOverlay())
            pumpNativeEvents(overlay)
            try await Task.sleep(for: .milliseconds(100))
            try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
            await fixture.capture.release()
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            #expect(abs(toolbar.frame.minX - (screen.frame.minX + 200)) <= 1)
            // Give any read started at commit time to reach the adapter before counting.
            try await Task.sleep(for: .milliseconds(100))
            #expect(await fixture.windows.calls == 1)
        }
    }

    @Test
    func heldWindowListDoesNotDelayOverlay() async throws {
        try await withSnapFixture { fixture, _, model in
            await fixture.windows.hold()
            try fixture.shortcuts.fire()
            try await eventually { try mainScreenOverlay() != nil }
            let overlay = try #require(try mainScreenOverlay())
            try await eventually { try overlayShowsFrozenFrame(overlay) }
            await fixture.windows.release()
        }
    }

    // v1-core::REQ-007–009: Copy and Save end the capture without history or a model request; the
    // selection can be adjusted first. The window is local (200, 150, 300, 200) of the main screen.
    // Not covered here: the real save panel and clipboard, and the modal failure alerts.
    @Test
    func copyPutsSelectionOnClipboardAndEndsCapture() async throws {
        try await withSnapFixture { fixture, screen, model in
            let historyCount = model.historyRecords.count
            let toolbar = try await selectWindow(fixture)
            try click(toolbar, at: toolbarIconCenter(toolbar, fromEnd: 2))
            try await eventually { try mainScreenOverlay() == nil && captureToolbar() == nil }
            let png = try #require(fixture.clipboard.written.last)
            #expect(try pngPixelSize(png) == pixelSize(width: 300, height: 200, on: screen))
            #expect(model.historyRecords.count == historyCount)
            #expect(await fixture.http.imageRequests.isEmpty)
        }
    }

    @Test
    func saveWritesSelectionWhereTheUserChoseAndEndsCapture() async throws {
        try await withSnapFixture { fixture, screen, model in
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent("vlmsnapper-save-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: target) }
            fixture.imageSaver.answer = .saveTo(target)
            let historyCount = model.historyRecords.count
            let toolbar = try await selectWindow(fixture)
            try click(toolbar, at: toolbarIconCenter(toolbar, fromEnd: 1))
            try await eventually { try mainScreenOverlay() == nil && captureToolbar() == nil }
            #expect(try pngPixelSize(Data(contentsOf: target)) == pixelSize(width: 300, height: 200, on: screen))
            let name = try #require(fixture.imageSaver.requests.last?.suggestedName)
            #expect(name.range(of: #"^vlmsnapper-\d{8}-\d{6}\.png$"#, options: .regularExpression) != nil)
            #expect(model.historyRecords.count == historyCount)
            #expect(await fixture.http.imageRequests.isEmpty)
        }
    }

    @Test
    func cancelledSaveKeepsTheSelection() async throws {
        try await withSnapFixture { fixture, _, model in
            fixture.imageSaver.answer = .cancel
            let toolbar = try await selectWindow(fixture)
            try click(toolbar, at: toolbarIconCenter(toolbar, fromEnd: 1))
            try await eventually { fixture.imageSaver.requests.count == 1 }
            pumpNativeEvents(toolbar)
            #expect(try mainScreenOverlay() != nil)
            #expect(captureToolbar() != nil)
            // The selection is still usable afterwards.
            try click(toolbar, at: toolbarIconCenter(toolbar, fromEnd: 2))
            try await eventually { fixture.clipboard.written.count == 1 }
        }
    }

    @Test
    func adjustedSelectionIsWhatCopyUses() async throws {
        try await withSnapFixture { fixture, screen, model in
            _ = try await selectWindow(fixture)
            let overlay = try requireFixture(try mainScreenOverlay())
            // Bottom-right handle of the window (500, 150) to (400, 200): the selection becomes (200, 200, 200, 150).
            try drag(overlay, from: NSPoint(x: 500, y: 150), to: NSPoint(x: 400, y: 200))
            try await eventually {
                guard let toolbar = captureToolbar() else { return false }
                return abs(toolbar.frame.maxY - (screen.frame.minY + 200 - 4)) <= 1
            }
            let toolbar = try requireFixture(captureToolbar())
            try click(toolbar, at: toolbarIconCenter(toolbar, fromEnd: 2))
            try await eventually { !fixture.clipboard.written.isEmpty }
            #expect(try pngPixelSize(try #require(fixture.clipboard.written.last))
                == pixelSize(width: 200, height: 150, on: screen))
        }
    }

    @Test
    func secondAdjustmentDuringCropIsWhatCopyUses() async throws {
        try await withSnapFixture { fixture, screen, _ in
            _ = try await selectWindow(fixture)
            let overlay = try requireFixture(try mainScreenOverlay())
            // Two releases before the first crop finishes: (200, 200, 200, 150), then (200, 175, 250, 175).
            try drag(overlay, from: NSPoint(x: 500, y: 150), to: NSPoint(x: 400, y: 200))
            try drag(overlay, from: NSPoint(x: 400, y: 200), to: NSPoint(x: 450, y: 175))
            let toolbar = try requireFixture(captureToolbar())
            try click(toolbar, at: toolbarIconCenter(toolbar, fromEnd: 2))
            try await eventually { !fixture.clipboard.written.isEmpty }
            let copied = try pngPixelSize(try #require(fixture.clipboard.written.last))
            #expect(copied == pixelSize(width: 250, height: 175, on: screen))
        }
    }

    @Test
    func doubleClickOnSaveOpensOneSavePanel() async throws {
        try await withSnapFixture { fixture, _, _ in
            fixture.imageSaver.answer = .cancel
            let toolbar = try await selectWindow(fixture)
            let save = try toolbarIconCenter(toolbar, fromEnd: 1)
            try click(toolbar, at: save)
            try click(toolbar, at: save)
            try await eventually { !fixture.imageSaver.requests.isEmpty }
            // Copy runs after both clicks were handled; the cancelled panel leaves Copy usable.
            try click(toolbar, at: toolbarIconCenter(toolbar, fromEnd: 2))
            try await eventually { fixture.clipboard.written.count == 1 }
            #expect(fixture.imageSaver.requests.count == 1)
        }
    }

    @Test
    func overlayTakesNoSelectionWhileSavePanelIsOpen() async throws {
        try await withSnapFixture { fixture, screen, _ in
            fixture.imageSaver.answer = .hold
            let toolbar = try await selectWindow(fixture)
            try click(toolbar, at: toolbarIconCenter(toolbar, fromEnd: 1))
            try await eventually { fixture.imageSaver.requests.count == 1 }
            let overlay = try requireFixture(try mainScreenOverlay())
            // A press outside the selection and a drag on its bottom-right handle: neither applies.
            try sendMouse(.leftMouseDown, at: NSPoint(x: 800, y: 500), to: overlay)
            try sendMouse(.leftMouseUp, at: NSPoint(x: 800, y: 500), to: overlay)
            try drag(overlay, from: NSPoint(x: 500, y: 150), to: NSPoint(x: 400, y: 200))
            #expect(captureToolbar() != nil)
            fixture.imageSaver.release(.cancelled)
            // The save action ends after the panel; a Copy click is taken once it has.
            try await eventually {
                if fixture.clipboard.written.isEmpty {
                    try click(toolbar, at: toolbarIconCenter(toolbar, fromEnd: 2))
                }
                return !fixture.clipboard.written.isEmpty
            }
            let copied = try pngPixelSize(try #require(fixture.clipboard.written.last))
            #expect(copied == pixelSize(width: 300, height: 200, on: screen))
        }
    }

    @Test
    func displayChangeAfterSelectionEndsCapture() async throws {
        try await withSnapFixture { fixture, _, model in
            let historyCount = model.historyRecords.count
            _ = try await selectWindow(fixture)
            let current = try #require(fixture.displayGeometries?.first)
            fixture.displayGeometries = [changedGeometry(current, scale: true)]
            fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            try await eventually { try mainScreenOverlay() == nil && captureToolbar() == nil }
            #expect(model.historyRecords.count == historyCount)
        }
    }

    @Test
    func displayChangeWhileReplacingAbandonsPendingCapture() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-invalidated-key")
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let previous = try #require(try mainScreenOverlay())
                try await eventually { try overlayShowsFrozenFrame(previous) }

                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 2 && mainScreenOverlay().map { $0 !== previous } == true
                }
                // Ending the first selection releases the activity the pending capture shares.
                fixture.displayGeometries = [changedGeometry(display.geometry, move: true)]
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                try await eventually { !captureOverlayIsVisible() && model.providerSnapshot.activity == nil }
                fixture.displayGeometries = [display.geometry]
                // The second freeze has not returned; a shortcut now must still show its overlay.
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 3 && mainScreenOverlay() != nil
                }
                let replacement = try #require(try mainScreenOverlay())
                await fixture.capture.release()
                try await eventually { try overlayShowsFrozenFrame(replacement) }
                #expect(replacement.isVisible)
                #expect(try mainScreenOverlay() === replacement)
            }
        }
    }

    @Test
    func displayChangeBetweenFreezeValidationAndObserverRegistrationIsNotLost() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.queuedDisplayGeometries = [[display.geometry], []]
            fixture.displayGeometries = []
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-display-race-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                try await eventually {
                    model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }
                try fixture.shortcuts.fire()
                try await eventually { fixture.displayReads >= 2 && model.providerSnapshot.activity == nil }
                #expect(!NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver })
                #expect(model.historyRecords.isEmpty)
                #expect(await fixture.http.imageRequests.isEmpty)
            }
        }
    }

    @Test
    func credentialValidationAndFreezingExcludeEachOtherThroughApplicationWiring() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-initial-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                try await eventually {
                    model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }

                await fixture.http.pause()
                model.credentialEditor.edit("fixture-replacement-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { await fixture.http.requests.count == 2 }
                var providerNavigations = 0
                model.onNavigate = { if $0 == .providerSettings { providerNavigations += 1 } }
                try fixture.shortcuts.fire()
                try await eventually { providerNavigations == 1 }
                #expect(await fixture.capture.requests == 0)
                #expect(await fixture.http.requests.count == 2)
                #expect(model.historyRecords.isEmpty)
                await fixture.http.release()
                try await eventually {
                    !model.credentialEditor.isSubmitting && model.providerReadiness
                        == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }

                await fixture.capture.allowSuspendedCapture()
                try fixture.shortcuts.fire()
                try await eventually { await fixture.capture.requests == 1 }
                try await eventually { model.providerSnapshot.blocksConfigurationChanges }
                model.credentialEditor.edit("fixture-after-capture-key")
                let blocked = model.providerSettingsConfiguration()
                #expect(!model.credentialEditor.submit(for: .deepSeek,
                    isReadOnly: blocked.snapshot.blocksConfigurationChanges, operation: blocked.onValidate))
                #expect(model.credentialEditor.value == "fixture-after-capture-key")
                #expect(await fixture.http.requests.count == 2)
                #expect(model.historyRecords.isEmpty)

                var permissionPrompts = 0
                model.onShowOnboarding = { permissionPrompts += 1 }
                await fixture.capture.release()
                try await eventually {
                    permissionPrompts == 1 && !model.providerSnapshot.blocksConfigurationChanges
                }
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { await fixture.http.requests.count == 3 }
                try await eventually { !model.credentialEditor.isSubmitting }
                #expect(model.historyRecords.isEmpty)
            }
        }
    }

    @Test
    func nativeOnboardingValidatesSelectsAndReturns() async throws {
        try await withFixture { fixture in
            try await fixture.withApplication { _ in
                let onboarding = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentViewController is NSHostingController<OnboardingContainerView>
                })
                try await eventually {
                    pumpNativeEvents(onboarding)
                    return onboarding.contentView?.bounds.width ?? 0 > 0
                }
                let onboardingContent = try #require(onboarding.contentView)
                onboardingContent.layoutSubtreeIfNeeded()
                // Point in the Provider row's trailing action in the fixed
                // production onboarding render; success requires actual routing.
                try await openProviderFromOnboarding(onboarding)
                try await eventually { !onboarding.isVisible }
                let management = try #require(NSApp.windows.first {
                    $0.isVisible && $0 !== onboarding && $0.title == "VLMSnapper"
                })
                try await eventually {
                    pumpNativeEvents(management)
                    return management.contentView.map { descendants($0).contains { $0 is NSSecureTextField } } == true
                }
                let content = try #require(management.contentView)
                let field = try #require(descendants(content)
                    .compactMap { $0 as? NSSecureTextField }.first)
                #expect(management.makeFirstResponder(field))
                let editor = try #require(field.currentEditor() as? NSTextView)
                editor.insertText("fixture-native-key", replacementRange: editor.selectedRange())
                pumpNativeEvents(management)
                editor.interpretKeyEvents([try #require(NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: management.windowNumber, context: nil, characters: "\r",
                    charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
                ))])
                try await eventually { await fixture.http.requests.count == 1 }
                try await eventually { await fixture.credentials.credential(for: .deepSeek) != nil }
                #expect(management.isVisible)
                #expect(!onboarding.isVisible)
                try await eventually {
                    pumpNativeEvents(management)
                    return descendants(content).compactMap { $0 as? NSPopUpButton }
                        .contains { $0.itemTitles.contains("fixture-vision") }
                }
                // Closing before choosing a model returns to onboarding, then
                // reopening uses persisted credentials rather than the old draft.
                management.performClose(nil)
                try await eventually { onboarding.isVisible && !management.isVisible }
                pumpNativeEvents(onboarding)
                try await openProviderFromOnboarding(onboarding)
                try await eventually {
                    pumpNativeEvents(management)
                    return management.isVisible && !onboarding.isVisible
                        && descendants(content).compactMap { $0 as? NSPopUpButton }
                            .contains { $0.isEnabled && $0.itemTitles.contains("fixture-vision") }
                }
                let picker = try #require(descendants(content).compactMap { $0 as? NSPopUpButton }
                    .first { $0.itemTitles.contains("fixture-vision") })
                #expect(management.isVisible)
                #expect(!onboarding.isVisible)
                let menu = try #require(picker.menu)
                let index = menu.indexOfItem(withTitle: "fixture-vision")
                #expect(index >= 0)
                let item = try #require(menu.item(at: index))
                _ = try #require(item.action)
                menu.performActionForItem(at: index)
                try await eventually { onboarding.isVisible && !management.isVisible }
                #expect(await fixture.http.requests.count == 1)
            }
            try await fixture.withModel { model in
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
                #expect(model.credentialEditor.value == "fixture-native-key")
            }
        }
    }

    @Test
    func applicationStartupOwnsRealWindowsAndReleasesPrimaryLock() async throws {
        try await withFixture { fixture in
            try await fixture.withApplication { application in
                let onboarding = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentViewController is NSHostingController<OnboardingContainerView>
                })
                #expect(onboarding.isVisible)
                let secondary = fixture.application()
                defer { secondary.stop() }
                #expect(try await secondary.start() == .secondary)
                #expect(fixture.shortcuts.activeRegistrations == 1)
                #expect(fixture.dependencyConstructions == 1)
                #expect(await application.prepareForTermination())
            }
            try await fixture.withApplication { _ in
                #expect(fixture.shortcuts.activeRegistrations == 1)
            }
        }
    }

    @Test
    func injectedUpdateEventsReachTheApplicationPresentation() async throws {
        try await withFixture { fixture in
            try await fixture.withModel { model in
                let updates = try #require(fixture.updates)
                #expect(await updates.configuration?.allowsAutomaticDownloads == false)
                let version = AvailableUpdateVersion(version: "2", displayVersion: "2.0")
                await updates.send(.available(version))
                #expect(model.updateState == .available(version))
                #expect(model.settings.updateState == .available(version))
            }
        }
    }

    @Test(arguments: [401, 500])
    func failedValidationKeepsCandidateAndAllowsManualRetry(status: Int) async throws {
        try await withFixture { fixture in
            await fixture.http.respond(with: status)
            try await fixture.withModel { model in
                let configuration = model.providerSettingsConfiguration()
                model.credentialEditor.edit("fixture-rejected-key")
                #expect(model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: configuration.onValidate
                ))
                try await eventually {
                    !model.credentialEditor.isSubmitting && model.providerSnapshot.phase == .failed
                }
                #expect(model.providerReadiness == .missing)
                #expect(model.credentialEditor.value == "fixture-rejected-key")
                #expect(model.credentialEditor.isDirty)
                #expect(await fixture.http.requests.count == 1)
                #expect(await fixture.credentials.credential(for: .deepSeek) == nil)

                await fixture.http.respond(with: 200)
                #expect(model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: configuration.onValidate
                ))
                try await eventually {
                    !model.credentialEditor.isSubmitting
                        && model.providerReadiness == .pendingModel(.deepSeek)
                }
                #expect(await fixture.http.requests.count == 2)
            }
        }
    }

    @Test
    func permissionAndRetentionUseOnlyTheIsolatedPreferences() async throws {
        try await withFixture { fixture in
            let defaults = try #require(UserDefaults(suiteName: fixture.suite))
            defaults.set(true, forKey: "screenCapturePermissionRequested")
            defaults.set(7, forKey: "historyRetentionDays")
            try await fixture.withModel { model in
                #expect(model.permission == .unavailable)
                #expect(model.retention == .sevenDays)
                model.managementCallbacks().onRetentionChange(.sixtyDays)
                try await eventually { model.retention == .sixtyDays }
                #expect(defaults.integer(forKey: "historyRetentionDays") == 60)
            }
            try await fixture.withModel { model in
                #expect(model.retention == .sixtyDays)
            }
        }
    }

    @Test
    func terminationPreparationDoesNotUnregisterBeforeExitIsCommitted() async throws {
        try await withFixture { fixture in
            try await fixture.withModel { model in
                #expect(fixture.shortcuts.activeRegistrations == 1)
                #expect(await model.prepareForTermination())
                #expect(fixture.shortcuts.activeRegistrations == 1)
                model.stop()
                #expect(fixture.shortcuts.activeRegistrations == 0)
                model.stop()
                #expect(fixture.shortcuts.activeRegistrations == 0)
            }
        }
    }

    @Test
    func validatesSelectsAndRestoresProviderThroughApplicationCallbacks() async throws {
        try await withFixture { fixture in
            try await fixture.withModel { model in
                #expect(model.providerReadiness == .missing)
                let configuration = model.providerSettingsConfiguration()
                model.credentialEditor.edit("fixture-not-a-real-key")
                let accepted = model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: configuration.onValidate
                )
                #expect(accepted)
                #expect(!model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: configuration.onValidate
                ))
                try await eventually {
                    !model.credentialEditor.isSubmitting
                        && model.providerSnapshot.availableModelIDs == ["fixture-vision"]
                        && model.providerReadiness == .pendingModel(.deepSeek)
                }
                #expect(model.providerSnapshot.availableModelIDs == ["fixture-vision"])
                #expect(model.providerReadiness == .pendingModel(.deepSeek))
                #expect(await fixture.http.requests.count == 1)
                #expect(await fixture.http.requests.first?.value(forHTTPHeaderField: "Authorization")
                    == "Bearer fixture-not-a-real-key")

                var completions = 0
                model.onProviderConfigurationCompleted = { completions += 1 }
                configuration.onSelectModel("fixture-vision")
                try await eventually { completions == 1 }
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
            }
            // Construct a fresh application model/session/coordinator over the same
            // isolated credential adapter and real metadata files.
            try await fixture.withModel { model in
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
                #expect(model.credentialEditor.value == "fixture-not-a-real-key")
                #expect(model.historyRecords.isEmpty)
                #expect(await fixture.http.requests.count == 1)
            }
        }
    }
}

@MainActor
private func eventually(file: String = #fileID, line: Int = #line, _ condition: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(try await condition()) {
        guard ContinuousClock.now < deadline else { throw FixtureError.deadline(file, line) }
        try Task.checkCancellation()
        await Task.yield()
    }
}

private enum FixtureError: Error {
    case deadline(String, Int), unexpectedOperation, state(String)
    case cleanup(operation: any Error, release: any Error)
}

private func requireFixture<T>(_ value: T?) throws -> T {
    guard let value else { throw FixtureError.state("Required fixture value is missing") }
    return value
}

@MainActor
private func renderedText(in window: NSWindow) throws -> String {
    pumpNativeEvents(window)
    let view = try XCTUnwrap(window.contentView)
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["en-US"]
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

@MainActor
private func withNativeApplicationEnvironment(_ operation: () async throws -> Void) async throws {
    let application = NSApplication.shared
    let previousDelegate = application.delegate
    let previousPolicy = application.activationPolicy()
    application.delegate = nil
    defer {
        application.delegate = previousDelegate
        _ = application.setActivationPolicy(previousPolicy)
    }
    guard application.setActivationPolicy(.accessory) else { throw FixtureError.state("Accessory activation policy was rejected") }
    try await operation()
}

@MainActor
private func pumpWindowActivationEvents() {
    if let event = NSApp.nextEvent(matching: .appKitDefined, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) {
        NSApp.sendEvent(event)
    }
    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
}

@MainActor
private func openProviderFromOnboarding(_ window: NSWindow) async throws {
    try await eventually {
        pumpNativeEvents(window)
        return window.contentView?.bounds.width ?? 0 > 0
    }
    let content = try requireFixture(window.contentView)
    let bitmap = try requireFixture(content.bitmapImageRepForCachingDisplay(in: content.bounds))
    content.cacheDisplay(in: content.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["en-US"]
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: requireFixture(bitmap.cgImage), options: [:]).perform([request])
    // Locate the visible button, not an old coordinate or the routing callback.
    let label = try requireFixture(request.results?.first {
        $0.topCandidates(1).first?.string == "Provider Settings"
    })
    let rectangle = label.boundingBox
    let local = NSPoint(x: rectangle.midX * content.bounds.width,
                        y: (content.isFlipped ? 1 - rectangle.midY : rectangle.midY) * content.bounds.height)
    try click(window, at: content.convert(local, to: nil))
    try await eventually { !window.isVisible }
}

@MainActor
private func editableSecureField(in window: NSWindow) async throws -> NSSecureTextField {
    try await eventually {
        pumpNativeEvents(window)
        return window.contentView.map {
            descendants($0).compactMap { $0 as? NSSecureTextField }.contains { $0.isEditable }
        } == true
    }
    let content = try requireFixture(window.contentView)
    return try requireFixture(descendants(content).compactMap { $0 as? NSSecureTextField }.first { $0.isEditable })
}

@MainActor
private func clickValidate(below field: NSTextField, in window: NSWindow) throws {
    pumpNativeEvents(window)
    let frame = field.convert(field.bounds, to: nil)
    try click(window, at: NSPoint(x: frame.maxX, y: frame.minY - 30))
}

@MainActor
private func click(_ window: NSWindow, at point: NSPoint) throws {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        window.sendEvent(try requireFixture(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1
        )))
    }
}

@MainActor
private func drag(_ window: NSWindow, from start: NSPoint, to end: NSPoint, trace: NativeWaitTrace? = nil) throws {
    for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
        trace?.record("before-mouse-\(type.rawValue)", window: window)
        window.sendEvent(try requireFixture(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1
        )))
        pumpNativeEvents(window)
        trace?.record("after-mouse-\(type.rawValue)", window: window)
    }
}

// Test-only, bounded state transitions. Never read titles, editor values,
// pasteboard contents, captured pixels or external application names.
@MainActor
private final class NativeWaitTrace {
    private let name: String
    private let start = ProcessInfo.processInfo.systemUptime
    private var previous = ""
    private var entries: [String] = []

    init(name: String) { self.name = name }

    func record(_ stage: String, window: NSWindow? = nil) {
        let windows = NSApp.windows.sorted { $0.windowNumber < $1.windowNumber }.map {
            "id=\($0.windowNumber),visible=\($0.isVisible),key=\($0.isKeyWindow),canKey=\($0.canBecomeKey),level=\($0.level.rawValue),size=\($0.contentView?.bounds.size ?? .zero)"
        }.joined(separator: ";")
        let state = "stage=\(stage) target=\(window?.windowNumber ?? -1) active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue) key=\(NSApp.keyWindow?.windowNumber ?? -1) main=\(NSApp.mainWindow?.windowNumber ?? -1) frontPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1) windows=[\(windows)]"
        guard state != previous else { return }
        previous = state
        if entries.count == 64 { entries.removeFirst() }
        entries.append("t=\(ProcessInfo.processInfo.systemUptime - start) \(state)")
    }

    func emit() {
        let header = "[NATIVE-DIAG] \(name) pid=\(ProcessInfo.processInfo.processIdentifier) elapsed=\(ProcessInfo.processInfo.systemUptime - start)"
        let output = ([header] + entries).joined(separator: "\n") + "\n"
        FileHandle.standardError.write(Data(output.utf8))
    }
}

@MainActor
private func clickRerun(_ window: NSWindow) throws {
    let content = try #require(window.contentView)
    // Measured from a production render with this one-line fixture result.
    // This SwiftUI button is not an NSButton; exercise actual mouse delivery.
    try click(window, at: NSPoint(x: content.bounds.midX + 55, y: content.bounds.height - 219))
}

@MainActor
enum DisplayChange: CaseIterable {
    case sleep, disconnect, scale, rotate, move
}

private func changedGeometry(
    _ value: CaptureDisplayGeometry,
    id: UInt32? = nil,
    scale: Bool = false,
    rotate: Bool = false,
    move: Bool = false
) -> CaptureDisplayGeometry {
    CaptureDisplayGeometry(
        displayID: id ?? value.displayID,
        logicalX: value.logicalX + (move ? 100 : 0), logicalY: value.logicalY,
        logicalWidth: value.logicalWidth, logicalHeight: value.logicalHeight,
        pixelWidth: value.pixelWidth + (scale ? 100 : 0), pixelHeight: value.pixelHeight,
        rotationDegrees: value.rotationDegrees + (rotate ? 90 : 0)
    )
}

@MainActor
private func makeCaptureReady(_ model: VLMSnapperApplicationModel, key: String) async throws {
    model.credentialEditor.edit(key)
    #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
        operation: model.providerSettingsConfiguration().onValidate))
    try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
    model.providerSettingsConfiguration().onSelectModel("fixture-vision")
    try await eventually {
        model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
    }
}

/// The selection overlay on the screen that `syntheticDisplay()` freezes.
@MainActor
private func mainScreenOverlay() throws -> NSWindow? {
    let screen = try requireFixture(NSScreen.main)
    return NSApp.windows.first {
        $0.isVisible && $0.level == .screenSaver && $0.frame == screen.frame
    }
}

@MainActor
private func captureOverlayIsVisible() -> Bool {
    NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver }
}

@MainActor
private func captureToolbar() -> NSWindow? {
    NSApp.windows.first { $0.isVisible && $0.contentView is NSHostingView<CaptureOperationToolbar> }
}

@MainActor
private func pressEscape(_ window: NSWindow) throws {
    window.sendEvent(try requireFixture(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
}

/// Sends Esc the way a key press arrives: to whichever window the application has made key.
@MainActor
private func pressEscapeThroughApplication() throws {
    let window = try requireFixture(NSApp.keyWindow)
    NSApp.sendEvent(try requireFixture(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
}

@MainActor
private func sendMouse(_ type: NSEvent.EventType, at point: NSPoint, to window: NSWindow) throws {
    window.sendEvent(try requireFixture(NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: 1, pressure: 1
    )))
    pumpNativeEvents(window)
}

/// Runs a capture-ready model whose window list holds one window at local (200, 150, 300, 200)
/// of the main screen, given to the list in global top-left coordinates.
@MainActor
private func withSnapFixture(
    windowList: Bool = true,
    _ body: @MainActor (ApplicationFixture, NSScreen, VLMSnapperApplicationModel) async throws -> Void
) async throws {
    try await withFixture { fixture in
        fixture.permissionGranted = true
        let display = try syntheticDisplay()
        await fixture.capture.provide(display)
        fixture.displayGeometries = [display.geometry]
        let screen = try #require(NSScreen.main)
        let flipHeight = try #require(NSScreen.screens.first).frame.height
        if windowList {
            let window = CaptureWindowSnapshotEntry(
                ownerProcessID: 4242, layer: 0, alpha: 1, isOnScreen: true,
                bounds: CGRect(
                    x: screen.frame.minX + 200,
                    y: flipHeight - (screen.frame.minY + 350),
                    width: 300,
                    height: 200
                )
            )
            await fixture.windows.provide(CaptureWindowSnapshot(windows: [window], dockProcessID: nil))
        }
        try await fixture.withModel { model in
            try await makeCaptureReady(model, key: "fixture-snap-key")
            try await body(fixture, screen, model)
        }
    }
}

/// Captures, clicks the fixture window and returns the toolbar shown for it.
@MainActor
private func selectWindow(_ fixture: ApplicationFixture) async throws -> NSWindow {
    try fixture.shortcuts.fire()
    let overlay = try await frozenMainOverlay()
    try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
    try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
    try await eventually { captureToolbar() != nil }
    let toolbar = try requireFixture(captureToolbar())
    pumpNativeEvents(toolbar)
    return toolbar
}

/// Centre of the toolbar's icon button `fromEnd` places before its last one (0 is Close, 1 Save, 2 Copy).
@MainActor
private func toolbarIconCenter(_ toolbar: NSWindow, fromEnd index: Int) throws -> NSPoint {
    let bounds = try requireFixture(toolbar.contentView).bounds
    let lastCenter = bounds.maxX - VLMSnapperUIConstants.toolbarPadding - VLMSnapperUIConstants.toolbarControlHeight / 2
    let step = VLMSnapperUIConstants.toolbarControlHeight + VLMSnapperUIConstants.toolbarControlGap
    return NSPoint(x: lastCenter - CGFloat(index) * step, y: bounds.midY)
}

private func pngPixelSize(_ data: Data) throws -> [Int] {
    let source = try requireFixture(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try requireFixture(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return [image.width, image.height]
}

@MainActor
private func pixelSize(width: CGFloat, height: CGFloat, on screen: NSScreen) -> [Int] {
    [Int((width * screen.backingScaleFactor).rounded()), Int((height * screen.backingScaleFactor).rounded())]
}

@MainActor
private func frozenMainOverlay() async throws -> NSWindow {
    try await eventually { try mainScreenOverlay() != nil }
    let overlay = try requireFixture(try mainScreenOverlay())
    try await eventually { try overlayShowsFrozenFrame(overlay) }
    pumpNativeEvents(overlay)
    return overlay
}

/// Captures with frames available immediately and drags a selection until the toolbar shows.
@MainActor
private func completeSelection(
    _ fixture: ApplicationFixture
) async throws -> (overlay: NSWindow, toolbar: NSWindow) {
    try fixture.shortcuts.fire()
    try await eventually { try mainScreenOverlay() != nil }
    let overlay = try requireFixture(try mainScreenOverlay())
    try await eventually { try overlayShowsFrozenFrame(overlay) }
    pumpNativeEvents(overlay)
    try drag(overlay, from: NSPoint(x: 100, y: 200), to: NSPoint(x: 300, y: 300))
    try await eventually { captureToolbar() != nil }
    return (overlay, try requireFixture(captureToolbar()))
}

/// Reads what the overlay shows at its centre: a pending overlay dims the live
/// screen (translucent), a frozen overlay shows the opaque frozen frame.
@MainActor
private func overlayShowsFrozenFrame(_ window: NSWindow) throws -> Bool {
    let layer = try requireFixture(window.contentView?.layer)
    let context = try requireFixture(CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: requireFixture(CGColorSpace(name: CGColorSpace.sRGB)),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.translateBy(x: -layer.bounds.midX, y: -layer.bounds.midY)
    layer.render(in: context)
    let alpha = try requireFixture(context.data).load(fromByteOffset: 3, as: UInt8.self)
    return alpha == 255
}

private func syntheticDisplay() throws -> FrozenCaptureDisplay {
    let screen = try #require(NSScreen.main)
    let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
    let geometry = try #require(currentCaptureDisplayGeometry(
        for: number.uint32Value, pointPixelScale: Float(screen.backingScaleFactor)
    ))
    let context = try #require(CGContext(data: nil, width: geometry.pixelWidth, height: geometry.pixelHeight,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: geometry.pixelWidth, height: geometry.pixelHeight))
    let image = try #require(context.makeImage())
    return FrozenCaptureDisplay(geometry: geometry, frame: FrozenDisplayFrame(image: image))
}

@MainActor
private func pumpNativeEvents(_ window: NSWindow) {
    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    window.layoutIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
}

@MainActor
private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

@MainActor
private func withFixture(_ operation: (ApplicationFixture) async throws -> Void) async throws {
    let fixture = try ApplicationFixture()
    defer { fixture.removeTemporaryState() }
    do {
        try await operation(fixture)
    } catch {
        let operationError = error
        do {
            try await fixture.waitForShortcutRelease()
        } catch {
            throw FixtureError.cleanup(operation: operationError, release: error)
        }
        throw error
    }
    try await fixture.waitForShortcutRelease()
}

@MainActor
private final class FixtureShortcutLease: GlobalShortcutRegistrationBackend {
    let backend: FixtureShortcuts
    init(backend: FixtureShortcuts) { self.backend = backend }
    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor @Sendable () -> Void) throws -> any GlobalShortcutRegistration {
        try backend.register(shortcut, handler: handler)
    }
}

@MainActor
private final class WeakShortcutLease {
    weak var value: FixtureShortcutLease?
    init(_ value: FixtureShortcutLease) { self.value = value }
}

@MainActor
private func stopFixture(excluding existingWindows: [NSWindow], stop: () -> Void) {
    precondition(withUnsafeCurrentTask { $0 != nil }, "Fixture cleanup requires a Swift Task")
    autoreleasepool {
        // Keep this fixture's windows alive across stop(), which closes them.
        let windows = NSApp.windows.filter { window in !existingWindows.contains { $0 === window } }
        stop()
        for window in windows {
            window.makeFirstResponder(nil)
            window.contentViewController = nil
            window.contentView = NSView()
            window.orderOut(nil)
        }
    }
}

private actor ControlledHistoryImages: ManagedScreenshotLoading {
    let store: FileSystemScreenshotStore
    private var paused = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var finishedCount = 0
    var pendingCount: Int { pending.count }
    init(store: FileSystemScreenshotStore) { self.store = store }
    func pause() { paused = true }
    func release(at index: Int) { pending.remove(at: index).resume() }
    func releaseAll() {
        paused = false
        let continuations = pending
        pending.removeAll()
        continuations.forEach { $0.resume() }
    }
    func loadIfOwned(_ screenshot: ManagedScreenshot) async throws -> Data {
        defer { finishedCount += 1 }
        if paused { await withCheckedContinuation { pending.append($0) } }
        return try await store.loadIfOwned(screenshot)
    }
}

@MainActor
private final class ApplicationFixture {
    let root: URL
    let suite = "VLMSnapperAppTests.\(UUID().uuidString)"
    let credentials = FixtureCredentials()
    let http = FixtureHTTP()
    let shortcuts = FixtureShortcuts()
    let capture = FixtureCapture()
    let windows = FixtureWindowListing()
    let clipboard = FixtureClipboard()
    let imageSaver = FixtureImageSaver()
    let displayNotifications = NotificationCenter()
    let workspaceNotifications = NotificationCenter()
    var displayGeometries: [CaptureDisplayGeometry]?
    var queuedDisplayGeometries: [[CaptureDisplayGeometry]] = []
    var displayReads = 0
    let pasteboard = NSPasteboard.withUniqueName()
    var permissionGranted = false
    var updates: FixtureUpdates?
    private(set) var dependencyConstructions = 0
    private var shortcutLeases: [WeakShortcutLease] = []

    func waitForShortcutRelease() async throws {
        // Cleanup must finish even when the operation's task was cancelled.
        try await Task { @MainActor in
            try await eventually {
                return autoreleasepool { self.shortcutLeases.allSatisfy { $0.value == nil } }
            }
        }.value
    }

    init() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func withModel(historyImageLoader: ControlledHistoryImages? = nil,
                   _ operation: (VLMSnapperApplicationModel) async throws -> Void) async throws {
        // Strong references: a freed window's address can be reused by a window this
        // fixture creates, so identifiers alone would skip that window at cleanup.
        let existingWindows = NSApp.windows
        let defaults = try requireFixture(UserDefaults(suiteName: suite))
        await UserDefaultsApplicationLanguageStore(defaults: defaults).save(.english)
        let model = try VLMSnapperApplicationModel(
            applicationSupportRoot: root,
            languageStore: UserDefaultsApplicationLanguageStore(defaults: defaults),
            defaults: defaults,
            dependencies: dependencies(),
            historyImageLoader: historyImageLoader
        )
        do {
            try await model.start()
            try await operation(model)
        } catch {
            await historyImageLoader?.releaseAll()
            await http.release()
            await capture.release()
            _ = await model.prepareForTermination()
            stopFixture(excluding: existingWindows) { model.stop() }
            throw error
        }
        await historyImageLoader?.releaseAll()
        await http.release()
        await capture.release()
        let canTerminate = await model.prepareForTermination()
        stopFixture(excluding: existingWindows) { model.stop() }
        guard canTerminate else { throw FixtureError.state("Model termination preparation was rejected") }
    }

    func application() -> VLMSnapperApplicationDelegate {
        VLMSnapperApplicationDelegate {
            let defaults = try requireFixture(UserDefaults(suiteName: self.suite))
            return ApplicationStartupDependencies(
                root: self.root, defaults: defaults, pasteboard: self.pasteboard, messaging: FixtureMessaging(),
                makeModelDependencies: { try self.dependencies() }
            )
        }
    }

    func withApplication(_ operation: (VLMSnapperApplicationDelegate) async throws -> Void) async throws {
        // Strong references: a freed window's address can be reused by a window this
        // fixture creates, so identifiers alone would skip that window at cleanup.
        let existingWindows = NSApp.windows
        let defaults = try requireFixture(UserDefaults(suiteName: suite))
        await UserDefaultsApplicationLanguageStore(defaults: defaults).save(.english)
        let application = application()
        let previousMenu = NSApp.mainMenu
        defer {
            NSApp.mainMenu = previousMenu
        }
        do {
            guard try await application.start() == .primary else { throw FixtureError.state("Expected primary application") }
            try await operation(application)
        } catch {
            await http.release()
            await capture.release()
            _ = await application.prepareForTermination()
            stopFixture(excluding: existingWindows) { application.stop() }
            throw error
        }
        await http.release()
        await capture.release()
        let canTerminate = await application.prepareForTermination()
        stopFixture(excluding: existingWindows) { application.stop() }
        guard canTerminate else { throw FixtureError.state("Application termination preparation was rejected") }
    }

    private func dependencies() throws -> ApplicationModelDependencies {
        dependencyConstructions += 1
        let preferences = try isolatedPreferences(suite: suite)
        return ApplicationModelDependencies(
                credentialStore: credentials,
                modelHTTP: http,
                operationHTTP: http,
                screenshotRoot: root.appendingPathComponent("Pictures"),
                permissionAuthorizer: FixturePermissions(granted: permissionGranted),
                permissionHistory: preferences.permission,
                retentionPreferences: preferences.retention,
                permissionChecker: FixturePermissions(granted: permissionGranted),
                frozenDisplayCapturer: capture,
                windowListing: windows,
                captureClipboard: clipboard,
                captureImageSaver: imageSaver,
                displayMonitor: CaptureDisplayMonitor(
                    notifications: displayNotifications,
                    workspaceNotifications: workspaceNotifications,
                    readGeometries: {
                        self.displayReads += 1
                        if !self.queuedDisplayGeometries.isEmpty {
                            return self.queuedDisplayGeometries.removeFirst()
                        }
                        return self.displayGeometries ?? CaptureDisplayMonitor.liveGeometries()
                    }
                ),
                loginService: FixtureLogin(),
                makeUpdateDriver: { handler in
                    let driver = FixtureUpdates(eventHandler: handler)
                    self.updates = driver
                    return driver
                },
                makeShortcutBackend: {
                    // The real coordinator owns this external-adapter lease;
                    // the fixture observes its release without retaining it.
                    let lease = FixtureShortcutLease(backend: self.shortcuts)
                    self.shortcutLeases.append(WeakShortcutLease(lease))
                    return lease
                }
        )
    }

    func removeTemporaryState() {
        pasteboard.releaseGlobally()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private func isolatedPreferences(suite: String) throws -> (
    permission: UserDefaultsPermissionRequestHistoryStore,
    retention: UserDefaultsRetentionPreferenceStore
) {
    guard let permissionDefaults = UserDefaults(suiteName: suite),
          let retentionDefaults = UserDefaults(suiteName: suite) else {
        throw FixtureError.unexpectedOperation
    }
    return (
        UserDefaultsPermissionRequestHistoryStore(defaults: permissionDefaults),
        UserDefaultsRetentionPreferenceStore(defaults: retentionDefaults)
    )
}

private actor FixtureMessaging: PrimaryInstanceMessaging {
    func beginObserving(_ handler: @escaping @Sendable () async -> Void) {}
    func requestActivation() {}
}

private actor FixtureCredentials: ProviderCredentialStoring {
    private var values: [ProviderID: ProviderCredential] = [:]
    func credential(for provider: ProviderID) -> ProviderCredential? { values[provider] }
    func replaceCredential(_ credential: ProviderCredential, for provider: ProviderID) {
        values[provider] = credential
    }
    func deleteCredential(for provider: ProviderID) { values[provider] = nil }
}

private actor FixtureHTTP: ProviderHTTPDataLoading, ProviderHTTPStreaming {
    private(set) var requests: [URLRequest] = []
    private var status = 200
    private var isPaused = false
    private var waiter: CheckedContinuation<Void, Never>?
    func pause() { isPaused = true }
    func release() {
        isPaused = false
        waiter?.resume()
        waiter = nil
        imageContinuation?.finish()
        imageContinuation = nil
    }
    func respond(with status: Int) { self.status = status }
    func data(for request: URLRequest) async -> ProviderHTTPResponse {
        requests.append(request)
        if isPaused { await withCheckedContinuation { waiter = $0 } }
        // Shape from https://api-docs.deepseek.com/api/list-models/ (2026-09-07).
        // The identifier is deliberately synthetic; no live credential is used.
        return ProviderHTTPResponse(
            data: Data(#"{"object":"list","data":[{"id":"fixture-vision","object":"model","owned_by":"deepseek"}]}"#.utf8),
            statusCode: status
        )
    }
    private var imagesAllowed = false
    private(set) var imageRequests: [URLRequest] = []
    private var imageContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    func allowImageRequests() { imagesAllowed = true }
    func stream(for request: URLRequest) throws -> ProviderHTTPStreamResponse {
        guard imagesAllowed else {
            Issue.record("Provider setup must not make an image request")
            throw FixtureError.unexpectedOperation
        }
        guard imageContinuation == nil else {
            Issue.record("An image request is already active")
            throw FixtureError.unexpectedOperation
        }
        imageRequests.append(request)
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        imageContinuation = pair.continuation
        return ProviderHTTPStreamResponse(statusCode: 200, headers: [:], body: pair.stream)
    }
    func finishImage(source: String, translation: String? = nil) throws {
        // DeepSeek chat SSE shape used by ProviderAdapterRecordedContractTests;
        // use the real JSON decoder/stream contract, not normalized fake events.
        var result: [String: Any] = ["source": source]
        if let translation {
            result = ["segments": [["id": "s1", "block": "p1", "kind": "paragraph",
                                     "source": source, "translation": translation]]]
        }
        let content = String(decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self)
        let chunk = try JSONSerialization.data(withJSONObject: [
            "id": "fixture-image", "choices": [["index": 0, "delta": ["content": content], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15]
        ])
        imageContinuation?.yield(Data("data: ".utf8) + chunk + Data("\n\ndata: [DONE]\n\n".utf8))
        imageContinuation?.finish()
        imageContinuation = nil
    }
}

private struct FixturePermissions: ScreenCapturePermissionAuthorizing, ScreenCapturePermissionChecking {
    let granted: Bool
    func preflightScreenCaptureAccess() async -> Bool { granted }
    func requestScreenCaptureAuthorization() async -> Bool { granted }
    func hasScreenCaptureAccess() -> Bool { granted }
}

private actor FixtureCapture: FrozenDisplayCapturing {
    private var display: FrozenCaptureDisplay?
    func provide(_ display: FrozenCaptureDisplay?) { self.display = display }
    private(set) var requests = 0
    private var allowed = false
    private var released = false
    private var framesHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func allowSuspendedCapture() {
        allowed = true
        released = false
    }
    /// Suspends captures until `release()`, then returns the provided display.
    func holdFrames() {
        framesHeld = true
        released = false
    }
    func release() {
        released = true
        framesHeld = false
        let suspended = waiters
        waiters.removeAll()
        suspended.forEach { $0.resume() }
    }
    func captureFrozenDisplays() async throws(CaptureDiscoveryError) -> FrozenDisplayBatch {
        requests += 1
        if framesHeld, !released { await withCheckedContinuation { waiters.append($0) } }
        if let display { return FrozenDisplayBatch(displays: [display]) }
        guard allowed else {
            Issue.record("Provider setup must not capture the screen")
            throw .permissionDenied
        }
        if !released { await withCheckedContinuation { waiters.append($0) } }
        throw .permissionDenied
    }
}

/// Clipboard double: records the PNG written by Copy.
@MainActor
private final class FixtureClipboard: CaptureImageClipboard {
    private(set) var written: [Data] = []
    func write(png: Data) -> Bool {
        written.append(png)
        return true
    }
}

/// Save double: answers like the save panel would and, when saving, writes the file as the live adapter does.
@MainActor
private final class FixtureImageSaver: CaptureImageSaving {
    /// `hold` keeps the panel open until `release(_:)`.
    enum Answer { case saveTo(URL), cancel, hold }
    var answer = Answer.cancel
    private(set) var requests: [(png: Data, suggestedName: String)] = []
    private var held: CheckedContinuation<CaptureImageSaveOutcome, Never>?
    func release(_ outcome: CaptureImageSaveOutcome) {
        held?.resume(returning: outcome)
        held = nil
    }
    func save(png: Data, suggestedName: String) async -> CaptureImageSaveOutcome {
        requests.append((png, suggestedName))
        switch answer {
        case .hold:
            return await withCheckedContinuation { held = $0 }
        case .cancel:
            return .cancelled
        case .saveTo(let url):
            do {
                try png.write(to: url, options: .atomic)
                return .saved(url)
            } catch {
                return .failed
            }
        }
    }
}

/// Window list for snap regions; by default there is none, so clicks keep their old meaning.
private actor FixtureWindowListing: CaptureWindowListing {
    private var snapshot: CaptureWindowSnapshot?
    /// Per-call lists, used in order before falling back to `snapshot`.
    private var queued: [CaptureWindowSnapshot?] = []
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func provide(_ snapshot: CaptureWindowSnapshot?) { self.snapshot = snapshot }
    func provide(perCall snapshots: [CaptureWindowSnapshot?]) { queued = snapshots }
    func hold() { held = true }
    /// Resumes held calls, newest first when `newestFirst` is set.
    func release(newestFirst: Bool = false) {
        held = false
        let suspended = newestFirst ? waiters.reversed() : waiters
        waiters.removeAll()
        suspended.forEach { $0.resume() }
    }
    private(set) var returned = 0
    private(set) var calls = 0
    func captureWindowSnapshot() async -> CaptureWindowSnapshot? {
        calls += 1
        let result = queued.isEmpty ? snapshot : queued.removeFirst()
        if held { await withCheckedContinuation { waiters.append($0) } }
        returned += 1
        return result
    }
}

private struct FixtureLogin: LoginItemServicing {
    func status() async -> LoginItemState { .unavailable }
    func register() async throws { throw FixtureError.unexpectedOperation }
    func unregister() async throws { throw FixtureError.unexpectedOperation }
    func openSystemSettings() async { Issue.record("Unexpected login settings request") }
}

private actor FixtureUpdates: UpdateDriving {
    private let eventHandler: @Sendable (UpdateLifecycleEvent) async -> Void
    private(set) var configuration: UpdateDriverConfiguration?
    init(eventHandler: @escaping @Sendable (UpdateLifecycleEvent) async -> Void) {
        self.eventHandler = eventHandler
    }
    func send(_ event: UpdateLifecycleEvent) async { await eventHandler(event) }
    func start(configuration: UpdateDriverConfiguration) { self.configuration = configuration }
    func setAutomaticallyChecks(_ enabled: Bool) {}
    func checkForUpdates() throws { throw FixtureError.unexpectedOperation }
    func beginDownload() throws { throw FixtureError.unexpectedOperation }
    func installNow() throws { throw FixtureError.unexpectedOperation }
}

@MainActor
private final class FixtureShortcuts: GlobalShortcutRegistrationBackend {
    private(set) var activeRegistrations = 0
    private var handler: (@MainActor @Sendable () -> Void)?
    func fire() throws {
        let registeredHandler = try #require(handler)
        registeredHandler()
    }
    func register(
        _ shortcut: GlobalShortcut,
        handler: @escaping @MainActor @Sendable () -> Void
    ) throws -> any GlobalShortcutRegistration {
        activeRegistrations += 1
        self.handler = handler
        return FixtureRegistration { [weak self] in
            self?.activeRegistrations -= 1
            self?.handler = nil
        }
    }
}

@MainActor
private final class FixtureRegistration: GlobalShortcutRegistration {
    private var release: (() -> Void)?
    init(release: @escaping () -> Void) { self.release = release }
    func unregister() {
        release?()
        release = nil
    }
}
