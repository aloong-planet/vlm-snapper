import AppKit
import Foundation
import SQLite3
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// Display tests inject OS notifications and geometry snapshots; physical
// hot-plug, display sleep and multi-monitor focus require hardware acceptance.
// Escape arriving before a press's request task reaches the session cannot be forced from here, so canceling
// that task when the capture ends or the box closes has no test that fails without it.
extension ProviderApplicationTests {
    @Test
    func escapeDuringARequestCancelsItAndLeavesTheCapture() async throws {
        try await withResultFixture { fixture, model in
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await eventually { resultBox() != nil }

            try pressEscape(overlay)

            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil && captureToolbar() == nil }
            try await eventually { model.providerSnapshot.activity == nil }
            #expect(model.historyRecords.first?.operation.status == .canceled, "saved before the activity is released")
        }
    }

    @Test
    func escapeFromTheBoxWithTheKeyboardLeavesTheCapture() async throws {
        try await withResultFixture { fixture, _ in
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Selectable text")
            try await eventually { resultBoxText() == "Selectable text" }
            let box = try #require(resultBox())
            box.makeKey()

            try pressEscape(box)

            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil }
        }
    }

    @Test
    func unsavedResultStaysUntilSavedOrDiscarded() async throws {
        try await withResultFixture { fixture, model in
            let database = try failSuccessfulSaves(fixture)
            defer { sqlite3_close(database) }
            let (overlay, toolbar) = try await completeSelection(fixture)
            let availableLabel = try translateLabelInk(toolbar)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Unsaved text")
            try await eventually { resultBoxPresentation()?.saveNotice != nil }
            try await waitForResultIdle(model)
            #expect(resultBoxText() == "Unsaved text")
            #expect(resultBoxPresentation()?.canCopy == true)
            #expect(resultBoxPresentation()?.canRetry == false)

            // Translate would send a request, so it looks unavailable and takes no press; closing keeps the result.
            let unavailableLabel = try translateLabelInk(toolbar)
            #expect(availableLabel - unavailableLabel > 0.2, "available \(availableLabel), unavailable \(unavailableLabel)")
            try await clickTranslate(toolbar)
            #expect(await fixture.http.imageRequests.count == 1)
            try clickResultBoxButton(try #require(resultBox()), fromEnd: 0)
            try await eventually { resultBox() == nil }
            try await clickExtract(toolbar)
            try await eventually { resultBoxText() == "Unsaved text" && resultBoxPresentation()?.saveNotice != nil }

            // The shortcut leaves it alone.
            let requests = await fixture.capture.requests
            try fixture.shortcuts.fire()
            pumpNativeEvents(overlay)
            #expect(await fixture.capture.requests == requests)

            // Leaving asks first, on the overlay; canceling changes nothing.
            try pressEscape(overlay)
            try await answerSheet(on: overlay, with: .alertSecondButtonReturn)
            #expect(overlay.isVisible)
            #expect(resultBoxPresentation()?.saveNotice != nil)

            // Retry Save writes the same result without another request.
            try #require(sqlite3_exec(database, "DROP TRIGGER box_save_failure", nil, nil, nil) == SQLITE_OK)
            let box = try #require(resultBox())
            try click(box, at: NSPoint(x: try #require(box.contentView).bounds.maxX - 32, y: 20))
            try await eventually { resultBoxPresentation()?.saveNotice == nil }
            try await eventually { model.historyRecords.first?.operation.sourceMarkdown == "Unsaved text" }
            #expect(await fixture.http.imageRequests.count == 1)
            try pressEscape(overlay)
            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil }
        }
    }

    @Test
    func leavingAgainWhileTheConfirmationIsOpenAsksOnlyOnce() async throws {
        try await withResultFixture { fixture, model in
            let database = try failSuccessfulSaves(fixture)
            defer { sqlite3_close(database) }
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Unsaved text")
            try await eventually { resultBoxPresentation()?.saveNotice != nil }
            try await waitForResultIdle(model)
            try pressEscape(overlay)
            try await eventually { overlay.attachedSheet != nil }

            // The toolbar stays clickable beside the sheet.
            try click(toolbar, at: try toolbarIconCenter(toolbar, fromEnd: 0))
            pumpNativeEvents(toolbar)
            try await Task.sleep(for: .milliseconds(50))
            try await answerSheet(on: overlay, with: .alertSecondButtonReturn)
            try await Task.sleep(for: .milliseconds(100))
            pumpNativeEvents(overlay)

            let secondSheet = overlay.attachedSheet
            #expect(secondSheet == nil, "keeping the result is the end of it")
            if let secondSheet { overlay.endSheet(secondSheet, returnCode: .alertSecondButtonReturn) }
            pumpNativeEvents(overlay)
            #expect(overlay.isVisible)
            #expect(resultBoxPresentation()?.saveNotice != nil)

            try pressEscape(overlay)
            try await answerSheet(on: overlay, with: .alertFirstButtonReturn)
            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil }
        }
    }

    @Test
    func escapeRightAfterAPressLeavesNothingRunning() async throws {
        try await withResultFixture { fixture, model in
            let (overlay, toolbar) = try await completeSelection(fixture)
            pumpNativeEvents(toolbar)
            try click(toolbar, at: NSPoint(x: 40, y: try #require(toolbar.contentView).bounds.midY))
            // Escape lands as close behind the press as a test can put it. Which step the request has
            // reached by then is not forced; wherever it is, the stream below stays open until it is canceled.
            var turns = 0
            while !model.isRunningResultRequest, turns < 10_000 {
                await Task.yield()
                turns += 1
            }
            #expect(model.isRunningResultRequest, "the press must have landed")

            try pressEscape(overlay)

            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil }
            try await eventually { model.providerSnapshot.activity == nil }
            #expect(await !fixture.http.hasActiveImageRequest)
        }
    }

    @Test
    func switchingAwayFromAnUnsavedResultAndBackKeepsIt() async throws {
        try await withResultFixture { fixture, model in
            let (overlay, toolbar) = try await completeSelection(fixture)
            model.changeTargetLanguage("ja")
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Saved text")
            try await eventually { resultBoxText() == "Saved text" }
            try await waitForResultIdle(model)

            let database = try failSuccessfulSaves(fixture)
            defer { sqlite3_close(database) }
            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 2 }
            try await fixture.http.finishImage(source: "Source", translation: "Unsaved translation")
            try await eventually { resultBoxPresentation()?.saveNotice != nil }
            try await waitForResultIdle(model)
            #expect(resultBoxText() == "Unsaved translation")

            // To the result that is saved: it shows and copies, and nothing is sent.
            try await clickExtract(toolbar)
            try await eventually { resultBoxText() == "Saved text" }
            #expect(resultBoxPresentation()?.saveNotice == nil)
            #expect(resultBoxPresentation()?.canRetry == false, "retrying would send a request")
            let box = try #require(resultBox())
            try clickResultBoxButton(box, fromEnd: 2)
            #expect(fixture.clipboard.writtenTexts.last == "Saved text")
            try clickResultBoxButton(box, fromEnd: 1)
            #expect(await fixture.http.imageRequests.count == 2)

            // And back: the unsaved result is still there.
            try await clickTranslate(toolbar)
            try await eventually { resultBoxText() == "Unsaved translation" && resultBoxPresentation()?.saveNotice != nil }
            try clickResultBoxButton(box, fromEnd: 2)
            #expect(fixture.clipboard.writtenTexts.last == "Unsaved translation")
            #expect(await fixture.http.imageRequests.count == 2)

            // With another language Translate would send a request, so it looks unavailable and takes no press.
            try await clickExtract(toolbar)
            try await eventually { resultBoxText() == "Saved text" }
            let availableLabel = try translateLabelInk(toolbar)
            model.changeTargetLanguage("ko")
            let unavailableLabel = try translateLabelInk(toolbar)
            #expect(availableLabel - unavailableLabel > 0.2, "available \(availableLabel), unavailable \(unavailableLabel)")
            try await clickTranslate(toolbar)
            #expect(resultBoxText() == "Saved text")
            #expect(await fixture.http.imageRequests.count == 2)
            model.changeTargetLanguage("ja")
            try await clickTranslate(toolbar)
            try await eventually { resultBoxText() == "Unsaved translation" }

            // Retry Save writes it, without another request.
            try #require(sqlite3_exec(database, "DROP TRIGGER box_save_failure", nil, nil, nil) == SQLITE_OK)
            try click(box, at: NSPoint(x: try #require(box.contentView).bounds.maxX - 32, y: 20))
            try await eventually { resultBoxPresentation()?.saveNotice == nil }
            try await eventually {
                model.historyRecords.contains { $0.operation.translationMarkdown?.contains("Unsaved translation") == true }
            }
            #expect(await fixture.http.imageRequests.count == 2)
            try pressEscape(overlay)
            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil }
        }
    }

    @Test
    func savingTheImageAfterAnOperationLeavesTheCapture() async throws {
        try await withResultFixture { fixture, model in
            let target = fixture.root.appendingPathComponent("saved-after-result.png")
            fixture.imageSaver.answer = .saveTo(target)
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Done")
            try await waitForResultIdle(model)

            try click(toolbar, at: try toolbarIconCenter(toolbar, fromEnd: 1))

            try await eventually { FileManager.default.fileExists(atPath: target.path) }
            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil && captureToolbar() == nil }
            #expect(model.historyRecords.count == 1, "saving the image makes no new history")
            #expect(await fixture.http.imageRequests.count == 1)
        }
    }

    @Test
    func savingOrCopyingWithAnUnsavedResultAsksAndKeepingItStays() async throws {
        try await withResultFixture { fixture, model in
            let database = try failSuccessfulSaves(fixture)
            defer { sqlite3_close(database) }
            let target = fixture.root.appendingPathComponent("saved-before-asking.png")
            fixture.imageSaver.answer = .saveTo(target)
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Unsaved text")
            try await eventually { resultBoxPresentation()?.saveNotice != nil }
            try await waitForResultIdle(model)

            try click(toolbar, at: try toolbarIconCenter(toolbar, fromEnd: 1))
            try await eventually { overlay.attachedSheet != nil }
            #expect(FileManager.default.fileExists(atPath: target.path), "the file is written before the question")
            try await answerSheet(on: overlay, with: .alertSecondButtonReturn)
            #expect(overlay.isVisible)
            #expect(resultBoxPresentation()?.saveNotice != nil)

            try await eventually {
                if overlay.attachedSheet == nil { try click(toolbar, at: try toolbarIconCenter(toolbar, fromEnd: 2)) }
                pumpNativeEvents(toolbar)
                return !fixture.clipboard.written.isEmpty
            }
            try await answerSheet(on: overlay, with: .alertSecondButtonReturn)
            #expect(overlay.isVisible)
            #expect(resultBoxPresentation()?.saveNotice != nil)

            try await eventually {
                if overlay.attachedSheet == nil { try pressEscape(overlay) }
                pumpNativeEvents(overlay)
                return overlay.attachedSheet != nil
            }
            try await answerSheet(on: overlay, with: .alertFirstButtonReturn)
            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil }
        }
    }

    @Test
    func discardingAnUnsavedResultLeavesTheCapture() async throws {
        try await withResultFixture { fixture, model in
            let database = try failSuccessfulSaves(fixture)
            defer { sqlite3_close(database) }
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Unsaved text")
            try await eventually { resultBoxPresentation()?.saveNotice != nil }
            try await waitForResultIdle(model)

            // Copying the image also asks before leaving.
            try click(toolbar, at: try toolbarIconCenter(toolbar, fromEnd: 2))
            try await answerSheet(on: overlay, with: .alertFirstButtonReturn)

            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil && captureToolbar() == nil }
            try await eventually { model.providerSnapshot.activity == nil }
            #expect(fixture.clipboard.written.count == 1)
        }
    }

    @Test
    func newCaptureClosesTheBoxOnlyOnceItsFramesAppear() async throws {
        try await withResultFixture { fixture, model in
            let (previous, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "First result")
            try await waitForResultIdle(model)
            let box = try #require(resultBox())

            await fixture.capture.holdFrames()
            try fixture.shortcuts.fire()
            try await eventually { try await fixture.capture.requests == 2 && mainScreenOverlay() !== previous && mainScreenOverlay() != nil }
            #expect(!box.isVisible, "the pending overlay's turn: the box waits with the toolbar")

            await fixture.capture.release()
            let next = try await frozenMainOverlay()
            try await eventually { !box.isVisible && !toolbar.isVisible && next !== previous }
            #expect(resultBox() == nil)

            // The new capture starts over: it selects again and has no result yet.
            try drag(next, from: NSPoint(x: 100, y: 200), to: NSPoint(x: 300, y: 300))
            try await eventually { captureToolbar() != nil }
            #expect(resultBox() == nil)
        }
    }

    @Test
    func failedFreezeRestoresTheBox() async throws {
        try await withResultFixture { fixture, model in
            let (previous, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "First result")
            try await waitForResultIdle(model)
            let box = try #require(resultBox())

            // A capture that fails leaves the previous selection and box exactly as they were.
            await fixture.capture.provide(nil)
            await fixture.capture.allowSuspendedCapture()
            var onboardingRequests = 0
            model.onShowOnboarding = { onboardingRequests += 1 }
            try fixture.shortcuts.fire()
            try await eventually { try await fixture.capture.requests == 2 && mainScreenOverlay() !== previous && mainScreenOverlay() != nil }
            #expect(!box.isVisible)
            await fixture.capture.release()
            try await eventually { onboardingRequests == 1 }
            #expect(previous.isVisible)
            #expect(box.isVisible)
            #expect(toolbar.isVisible)
            #expect(resultBoxText() == "First result")

            // The box still works: the reservation for the failed capture is gone.
            try clickResultBoxButton(box, fromEnd: 1)
            try await eventually { await fixture.http.imageRequests.count == 2 }
            try await fixture.http.finishImage(source: "Second result")
            try await eventually { resultBoxText() == "Second result" && resultBoxPresentation()?.showsProgress == false }
        }
    }

    @Test
    func escapeBeforeNewFramesLeavesTheCaptureAndItsBox() async throws {
        try await withResultFixture { fixture, model in
            let (previous, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "First result")
            try await waitForResultIdle(model)

            await fixture.capture.holdFrames()
            try fixture.shortcuts.fire()
            try await eventually { try await fixture.capture.requests == 2 && mainScreenOverlay() !== previous && mainScreenOverlay() != nil }
            let pending = try #require(try mainScreenOverlay())
            pumpNativeEvents(pending)
            try pressEscape(pending)
            try await eventually { !captureOverlayIsVisible() }
            await fixture.capture.release()
            try await eventually { model.providerSnapshot.activity == nil }

            #expect(resultBox() == nil)
            #expect(captureToolbar() == nil)
            #expect(!toolbar.isVisible)
            #expect(model.historyRecords.first?.operation.sourceMarkdown == "First result")
        }
    }

    @Test
    func selectionDisplayChangeDuringARequestEndsTheCapture() async throws {
        try await withResultFixture { fixture, model in
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await eventually { resultBox() != nil }

            // An unchanged geometry leaves everything alone.
            let reads = fixture.displayReads
            fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            try await eventually { fixture.displayReads > reads }
            #expect(overlay.isVisible)
            #expect(resultBox() != nil)
            #expect(toolbar.isVisible)

            let current = try #require(fixture.displayGeometries?.first)
            fixture.displayGeometries = [changedGeometry(current, scale: true)]
            fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil && captureToolbar() == nil }
            try await eventually { model.providerSnapshot.activity == nil }
            try await eventually { model.historyRecords.first?.operation.status == .canceled }
            #expect(fixture.resultLossNotifier.count == 0)
        }
    }

    @Test
    func selectionDisplayChangeWithAnUnsavedResultReportsItsLoss() async throws {
        try await withResultFixture { fixture, model in
            let database = try failSuccessfulSaves(fixture)
            defer { sqlite3_close(database) }
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Unsaved text")
            try await eventually { resultBoxPresentation()?.saveNotice != nil }

            let current = try #require(fixture.displayGeometries?.first)
            fixture.displayGeometries = [changedGeometry(current, rotate: true)]
            fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil }
            try await eventually { fixture.resultLossNotifier.count == 1 }
            try await eventually { model.providerSnapshot.activity == nil }
        }
    }

    @Test
    func terminationDuringARequestCancelsItAndLeavesTheCapture() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await eventually { resultBox() != nil }

            #expect(await model.prepareForTermination())

            #expect(try mainScreenOverlay() == nil)
            #expect(resultBox() == nil)
            #expect(model.historyRecords.first?.operation.status == .canceled, "saved before termination goes on")
        }
    }

    @Test
    func terminationAsksOnTheOverlayAboutAnUnsavedResult() async throws {
        try await withResultFixture { fixture, model in
            let database = try failSuccessfulSaves(fixture)
            defer { sqlite3_close(database) }
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Unsaved text")
            try await eventually { resultBoxPresentation()?.saveNotice != nil }
            try await waitForResultIdle(model)

            let refused = Task { @MainActor in await model.prepareForTermination() }
            try await answerSheet(on: overlay, with: .alertSecondButtonReturn)
            #expect(await refused.value == false)
            #expect(overlay.isVisible)
            #expect(resultBoxPresentation()?.saveNotice != nil)

            let accepted = Task { @MainActor in await model.prepareForTermination() }
            try await answerSheet(on: overlay, with: .alertFirstButtonReturn)
            #expect(await accepted.value)
            #expect(try mainScreenOverlay() == nil)
            #expect(resultBox() == nil)
        }
    }
}
