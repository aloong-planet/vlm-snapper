import AppKit
import Foundation
import SQLite3
import SwiftUI
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// History retry tests exercise production callbacks and rebuild the model from disk.
// History retries remain inline; double clicking no longer opens a result window.
// Production callback tests do not claim installed-app physical Retry clicks.
extension ProviderApplicationTests {
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
                #expect(resultBox() == nil)
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
                let prepared = try await store.prepareOperation(screenshot: screenshot,
                    selection: ProviderSelection(providerID: "deepseek", modelID: "archived-model"),
                    operation: .extractText)
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
                #expect(resultBox() == nil)

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
}
