import AppKit
import Foundation
import SwiftUI
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// Result box (v1-core::REQ-010–012): whether the box sits above the overlay on screen, selecting and
// copying while the application is not active, and a second display need the installed build.
// `aLanguageRowChoosesTheNextTranslationsLanguage` presses a real row; other sequences call the toolbar's
// language callback directly, to keep the catalog's long list out of them.
extension ProviderApplicationTests {
    @Test
    func operationKeepsTheCaptureScreenAndStreamsIntoTheResultBox() async throws {
        try await withResultFixture { fixture, model in
            let (overlay, toolbar) = try await completeSelection(fixture)
            #expect(resultBox() == nil)
            let visibleBefore = NSApp.windows.filter(\.isVisible)

            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await eventually { resultBox() != nil }

            #expect(overlay.isVisible)
            #expect(toolbar.isVisible)
            let added = NSApp.windows.filter { window in
                window.isVisible && !visibleBefore.contains { $0 === window }
            }
            #expect(added.count == 1 && added.first === resultBox(), "the box is the only new window")
            #expect(model.providerSnapshot.activity == .modelRequest)
            #expect(resultBoxPresentation()?.providerSummary == "DeepSeek · fixture-vision")

            try await fixture.http.streamImage(content: #"{"source":"Partial"#)
            try await eventually { resultBoxText() == "Partial" }
            #expect(resultBoxPresentation()?.showsProgress == true)

            try await fixture.http.streamImage(content: #" text"}"#, finishReason: "stop")
            try await eventually { resultBoxText() == "Partial text" && resultBoxPresentation()?.showsProgress == false }
            try await eventually { model.historyRecords.first?.operation.sourceMarkdown == "Partial text" }
            // The open capture still holds the activity (v1-core::REQ-012/AC-08).
            try await eventually { model.providerSnapshot.activity == .capture }
            #expect(model.providerSnapshot.blocksConfigurationChanges)
            #expect(overlay.isVisible)

            try pressEscape(overlay)
            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil && captureToolbar() == nil }
            try await eventually { model.providerSnapshot.activity == nil }
            #expect(model.historyRecords.count == 1)
        }
    }

    @Test
    func selectionIsLockedOnceAnOperationStarts() async throws {
        try await withResultFixture { fixture, model in
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            let toolbarFrame = toolbar.frame
            let height = try #require(overlay.contentView).bounds.height

            // A corner handle, the inside of the selection, and outside it.
            try drag(overlay, from: NSPoint(x: 100, y: 200), to: NSPoint(x: 50, y: 150))
            try drag(overlay, from: NSPoint(x: 200, y: 250), to: NSPoint(x: 260, y: 310))
            try drag(overlay, from: NSPoint(x: 500, y: min(500, height - 50)), to: NSPoint(x: 600, y: min(600, height - 10)))
            pumpNativeEvents(overlay)
            #expect(toolbar.frame == toolbarFrame)

            try await fixture.http.finishImage(source: "Done")
            try await waitForResultIdle(model)
            try click(toolbar, at: try toolbarIconCenter(toolbar, fromEnd: 2))
            try await eventually { fixture.clipboard.written.count == 1 }
            let screen = try #require(NSScreen.main)
            #expect(try pngPixelSize(fixture.clipboard.written[0]) == pixelSize(width: 200, height: 100, on: screen))
        }
    }

    @Test
    func oneBoxShowsOneOperationAndReturningSendsNoRequest() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await eventually { resultBox() != nil }
            let box = try #require(resultBox())
            let frame = box.frame

            // Another operation waits for the running one; a request would trip the HTTP fixture.
            try await clickTranslate(toolbar)
            #expect(await fixture.http.imageRequests.count == 1)
            try await clickExtract(toolbar)
            #expect(await fixture.http.imageRequests.count == 1)

            try await fixture.http.finishImage(source: "Extracted")
            try await eventually { resultBoxText() == "Extracted" && resultBoxPresentation()?.showsProgress == false }
            try await waitForResultIdle(model)

            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 2 }
            try await fixture.http.finishImage(source: "Source", translation: "Translated")
            try await eventually { resultBoxText() == "Translated" && resultBoxPresentation()?.showsProgress == false }
            try await waitForResultIdle(model)
            #expect(resultBox() === box)
            #expect(box.frame == frame)
            #expect(NSApp.windows.filter { $0.isVisible && $0.contentView is NSHostingView<CaptureResultBoxView> }.count == 1)

            try await clickExtract(toolbar)
            try await eventually { resultBoxText() == "Extracted" }
            try await clickTranslate(toolbar)
            try await eventually { resultBoxText() == "Translated" }
            #expect(await fixture.http.imageRequests.count == 2)
            try await eventually { model.historyRecords.count == 2 }

            // Copying takes the text of the operation on show.
            let current = try #require(resultBox())
            try clickResultBoxButton(current, fromEnd: 2)
            #expect(fixture.clipboard.writtenTexts == ["Translated"])
        }
    }

    @Test
    func anotherLanguageIsANewTranslationAndRetryKeepsItsLanguage() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)
            model.changeTargetLanguage("zh-Hans")
            @MainActor func languages() -> [String?] {
                model.historyRecords.map(\.operation.targetLanguage).sorted { ($0 ?? "") < ($1 ?? "") }
            }

            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Source", translation: "中文译文")
            try await eventually { resultBoxText() == "中文译文" && resultBoxPresentation()?.showsProgress == false }
            try await waitForResultIdle(model)
            try await eventually { model.historyRecords.count == 1 }
            let chineseTitle = resultBoxPresentation()?.title

            // Changing the language alone sends nothing and leaves the box as it is.
            model.changeTargetLanguage("ja")
            pumpNativeEvents(toolbar)
            #expect(await fixture.http.imageRequests.count == 1)
            #expect(resultBoxPresentation()?.title == chineseTitle)
            #expect(resultBoxText() == "中文译文")

            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 2 }
            try await fixture.http.finishImage(source: "Source", translation: "日本語の訳")
            try await eventually { resultBoxText() == "日本語の訳" && resultBoxPresentation()?.showsProgress == false }
            try await waitForResultIdle(model)
            try await eventually { model.historyRecords.count == 2 }
            #expect(languages() == ["ja", "zh-Hans"])
            let shared = Set(model.historyRecords.map(\.operation.screenshot.path))
            #expect(shared.count == 1)

            // Retry stays on its record and language, whatever the toolbar's language is by then.
            model.changeTargetLanguage("en")
            let box = try #require(resultBox())
            try clickResultBoxButton(box, fromEnd: 1)
            try await eventually { await fixture.http.imageRequests.count == 3 }
            try await fixture.http.finishImage(source: "Source", translation: "新しい訳")
            try await eventually { resultBoxText() == "新しい訳" && resultBoxPresentation()?.showsProgress == false }
            try await waitForResultIdle(model)
            try await eventually {
                model.historyRecords.contains { $0.operation.translationMarkdown?.contains("新しい訳") == true }
            }
            #expect(languages() == ["ja", "zh-Hans"])
            #expect(model.historyRecords.contains { $0.operation.targetLanguage == "zh-Hans" && $0.operation.translationMarkdown?.contains("中文译文") == true })

            // Back to an earlier language is another new record, and its failure changes nothing else.
            model.changeTargetLanguage("zh-Hans")
            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 4 }
            await fixture.http.failImage()
            try await eventually {
                if case .failure = resultBoxPresentation()?.body { return true }
                return false
            }
            try await eventually { model.historyRecords.count == 3 }
            #expect(languages() == ["ja", "zh-Hans", "zh-Hans"])
            #expect(model.historyRecords.contains { $0.operation.status == .failed })
            #expect(model.historyRecords.contains { $0.operation.translationMarkdown?.contains("中文译文") == true })
        }
    }

    @Test
    func closingTheBoxDuringARequestCancelsItAndPressingAgainSendsNothing() async throws {
        try await withResultFixture { fixture, model in
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await eventually { resultBox() != nil }
            try await fixture.http.streamImage(content: #"{"source":"Partial"#)
            try await eventually { resultBoxText() == "Partial" }

            try clickResultBoxButton(try #require(resultBox()), fromEnd: 0)
            try await eventually { resultBox() == nil }
            #expect(overlay.isVisible)
            #expect(toolbar.isVisible)
            try await eventually { model.historyRecords.first?.operation.status == .canceled }
            try await eventually { await !fixture.http.hasActiveImageRequest }
            try await waitForResultIdle(model)
            #expect(model.historyRecords.first?.operation.sourceMarkdown == nil, "no partial text is kept")

            try await clickExtract(toolbar)
            try await eventually { resultBox() != nil }
            try await eventually {
                if case .canceled = resultBoxPresentation()?.body { return true }
                return false
            }
            #expect(await fixture.http.imageRequests.count == 1)

            let box = try #require(resultBox())
            let id = try #require(model.historyRecords.first?.id)
            try clickResultBoxButton(box, fromEnd: 1)
            try await eventually { await fixture.http.imageRequests.count == 2 }
            try await fixture.http.finishImage(source: "Second try")
            try await eventually { model.historyRecords.first?.operation.sourceMarkdown == "Second try" }
            #expect(model.historyRecords.count == 1)
            #expect(model.historyRecords.first?.id == id)
        }
    }

    @Test
    func changingTheLanguageDuringATranslationAffectsOnlyTheNextPress() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)
            model.changeTargetLanguage("zh-Hans")
            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await eventually { resultBoxPresentation() != nil }
            let title = resultBoxPresentation()?.title

            model.changeTargetLanguage("ja")
            pumpNativeEvents(toolbar)
            #expect(resultBoxPresentation()?.title == title, "the box keeps naming the language being translated")

            try await fixture.http.finishImage(source: "Source", translation: "中文译文")
            try await eventually { resultBoxText() == "中文译文" }
            try await waitForResultIdle(model)
            #expect(resultBoxPresentation()?.title == title)
            try await eventually { model.historyRecords.first?.operation.targetLanguage == "zh-Hans" }
            #expect(model.historyRecords.count == 1)

            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 2 }
            try await fixture.http.finishImage(source: "Source", translation: "日本語の訳")
            try await eventually { resultBoxText() == "日本語の訳" }
            try await waitForResultIdle(model)
            try await eventually { model.historyRecords.count == 2 }
            #expect(resultBoxPresentation()?.title != title)
            #expect(Set(model.historyRecords.map(\.operation.targetLanguage)) == ["zh-Hans", "ja"])
        }
    }

    @Test
    func shortcutDuringARequestDoesNothing() async throws {
        try await withResultFixture { fixture, model in
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await eventually { model.providerSnapshot.activity == .modelRequest }

            try fixture.shortcuts.fire()
            pumpNativeEvents(overlay)
            // Read after something that arrives later, so an accepted shortcut has time to reach the capture.
            try await fixture.http.finishImage(source: "Done")
            try await eventually { resultBoxText() == "Done" }
            try await waitForResultIdle(model)

            #expect(await fixture.capture.requests == 1)
            #expect(try mainScreenOverlay() === overlay)
            #expect(overlay.isVisible)
            #expect(toolbar.isVisible)
        }
    }

    @Test
    func copyAndSaveWaitForARunningRequest() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await eventually { resultBox() != nil }
            pumpNativeEvents(toolbar)

            // Each in its own turn, and read after the request ends: an accepted press acts in between.
            try click(toolbar, at: try toolbarIconCenter(toolbar, fromEnd: 2))
            await settleToolbarAction(toolbar)
            try click(toolbar, at: try toolbarIconCenter(toolbar, fromEnd: 1))
            await settleToolbarAction(toolbar)
            try await fixture.http.finishImage(source: "Done")
            try await waitForResultIdle(model)
            #expect(fixture.clipboard.written.isEmpty)
            #expect(fixture.imageSaver.requests.isEmpty)
            #expect(try mainScreenOverlay() != nil)

            pumpNativeEvents(toolbar)
            try click(toolbar, at: try toolbarIconCenter(toolbar, fromEnd: 2))
            try await eventually { fixture.clipboard.written.count == 1 }
            try await eventually { try mainScreenOverlay() == nil && resultBox() == nil }
        }
    }

    @Test
    func toolbarMovesBesideTheBoxWhenTheBoxWouldCoverIt() async throws {
        try await withResultFixture { fixture, _ in
            let screen = try #require(NSScreen.main)
            try fixture.shortcuts.fire()
            let overlay = try await frozenMainOverlay()
            // Under where the box opens: near the right edge and the top.
            let right = screen.visibleFrame.maxX - screen.frame.minX - 40
            let top = screen.visibleFrame.maxY - screen.frame.minY - 100
            try drag(overlay, from: NSPoint(x: right - 240, y: top - 100), to: NSPoint(x: right, y: top))
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            pumpNativeEvents(toolbar)
            let original = toolbar.frame
            let inset = CaptureResultBoxMetrics.edgeInset
            let boxHeight = min(screen.visibleFrame.height - 2 * inset, CaptureResultBoxMetrics.maximumHeight)
            let opening = CGRect(
                x: screen.visibleFrame.maxX - inset - CaptureResultBoxMetrics.width,
                y: screen.visibleFrame.maxY - inset - boxHeight,
                width: CaptureResultBoxMetrics.width,
                height: boxHeight
            )
            #expect(original.intersects(opening), "the toolbar must start where the box opens")

            try await clickExtract(toolbar)
            try await eventually { resultBox() != nil }
            let box = try #require(resultBox())
            #expect(box.frame == opening)
            #expect(toolbar.frame.maxX == box.frame.minX - VLMSnapperUIConstants.toolbarResultBoxGap)
            #expect(toolbar.frame.minY == original.minY)
            // Front to back; `orderedWindows` leaves panels out.
            let order = try #require(NSWindow.windowNumbers(options: [])?.map(\.intValue))
            let toolbarPlace = try #require(order.firstIndex(of: toolbar.windowNumber))
            let boxPlace = try #require(order.firstIndex(of: box.windowNumber))
            #expect(toolbarPlace < boxPlace, "the toolbar stays in front of the box")

            // Dragging the box does not move the toolbar again.
            let beside = toolbar.frame
            pumpNativeEvents(box)
            let header = NSPoint(x: box.frame.width / 2, y: box.frame.height - CaptureResultBoxMetrics.headerHeight / 2)
            try drag(box, from: header, to: NSPoint(x: header.x - 120, y: header.y))
            #expect(box.frame.minX == opening.minX - 120)
            #expect(toolbar.frame == beside)

            try clickResultBoxButton(box, fromEnd: 0)
            try await eventually { resultBox() == nil }
            #expect(toolbar.frame == original, "it goes back when the box closes")
        }
    }

    @Test
    func aLongerAbbreviationKeepsTheToolbarBesideTheBox() async throws {
        try await withResultFixture { fixture, _ in
            let screen = try #require(NSScreen.main)
            try fixture.shortcuts.fire()
            let overlay = try await frozenMainOverlay()
            let right = screen.visibleFrame.maxX - screen.frame.minX - 40
            let top = screen.visibleFrame.maxY - screen.frame.minY - 100
            try drag(overlay, from: NSPoint(x: right - 240, y: top - 100), to: NSPoint(x: right, y: top))
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            try await clickExtract(toolbar)
            try await eventually { resultBox() != nil }
            let box = try #require(resultBox())
            pumpNativeEvents(toolbar)
            let width = toolbar.frame.width

            try await chooseLanguage("aeb", in: toolbar)

            try await eventually {
                pumpNativeEvents(toolbar)
                return toolbar.frame.width > width
                    && toolbar.frame.maxX == box.frame.minX - VLMSnapperUIConstants.toolbarResultBoxGap
            }
        }
    }

    @Test
    func aLanguageRowChoosesTheNextTranslationsLanguage() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)

            try await chooseLanguage("ja", in: toolbar)
            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Source", translation: "日本語の訳")
            try await waitForResultIdle(model)

            try await eventually { model.historyRecords.first?.operation.targetLanguage == "ja" }
        }
    }

    // Shaped after stored translations: several sentences in a block, including a list item.
    @Test
    func copyingATranslationKeepsItsBlocksAndListMarkers() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(segments: [
                ["id": "s1", "block": "b1", "kind": "heading", "source": "Title", "translation": "标题"],
                ["id": "s2", "block": "b2", "kind": "paragraph", "source": "One.", "translation": "第一句。"],
                ["id": "s3", "block": "b2", "kind": "paragraph", "source": "Two.", "translation": "第二句。"],
                ["id": "s4", "block": "b3", "kind": "listItem", "source": "Three.", "translation": "列表第一句。"],
                ["id": "s5", "block": "b3", "kind": "listItem", "source": "Four.", "translation": "列表第二句。"],
                ["id": "s6", "block": "b4", "kind": "listItem", "source": "Five", "translation": "第二项"],
            ])
            try await eventually { resultBoxPresentation()?.canCopy == true && resultBoxPresentation()?.showsProgress == false }
            try await waitForResultIdle(model)
            pumpNativeEvents(try #require(resultBox()))

            try clickResultBoxButton(try #require(resultBox()), fromEnd: 2)

            #expect(fixture.clipboard.writtenTexts.last == "标题\n\n第一句。第二句。\n\n- 列表第一句。列表第二句。\n\n- 第二项")
        }
    }

    @Test
    func copyingDuringATranslationTakesWhatHasArrivedWithItsStructure() async throws {
        try await withResultFixture { fixture, _ in
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.streamImage(content: #"{"segments":[{"id":"s1","block":"b1","kind":"heading","source":"Title","translation":"标题"},{"id":"s2","block":"b2","kind":"listItem","source":"One","translation":"第一项"},"#)
            try await eventually { resultBoxText()?.contains("第一项") == true }
            #expect(resultBoxPresentation()?.showsProgress == true, "the stream is still open")
            pumpNativeEvents(try #require(resultBox()))

            try clickResultBoxButton(try #require(resultBox()), fromEnd: 2)

            #expect(fixture.clipboard.writtenTexts.last == "标题\n\n- 第一项")
        }
    }

    @Test
    func aToolbarClearOfTheBoxStaysWhereItIs() async throws {
        try await withSnapFixture { fixture, _, _ in
            await fixture.http.allowImageRequests()
            let toolbar = try await selectWindow(fixture)
            pumpNativeEvents(toolbar)
            let original = toolbar.frame

            try await clickExtract(toolbar)
            try await eventually { resultBox() != nil }
            let box = try #require(resultBox())
            #expect(!original.intersects(box.frame), "the fixture window's toolbar must start clear of the box")
            #expect(toolbar.frame == original)

            try await eventually { await fixture.http.imageRequests.count == 1 }
            try clickResultBoxButton(box, fromEnd: 0)
            try await eventually { resultBox() == nil }
            #expect(toolbar.frame == original)
        }
    }

    // On a short display the box reaches down to this toolbar and it moves aside, as on CI, so this
    // test holds on any display and does not say whether the toolbar moved while the box is open.
    @Test
    func wholeDisplaySelectionKeepsTheBoxInPlaceAndTheToolbarClearOfIt() async throws {
        try await withSnapFixture { fixture, screen, _ in
            await fixture.http.allowImageRequests()
            try fixture.shortcuts.fire()
            let overlay = try await frozenMainOverlay()
            // Away from the fixture's one window: the desktop, so the whole display.
            let desktop = NSPoint(x: screen.frame.width - 40, y: 100)
            try sendMouse(.leftMouseDown, at: desktop, to: overlay)
            try sendMouse(.leftMouseUp, at: desktop, to: overlay)
            try await eventually { captureToolbar() != nil }
            let toolbar = try #require(captureToolbar())
            pumpNativeEvents(toolbar)
            let originalX = toolbar.frame.minX

            try await clickExtract(toolbar)
            try await eventually { resultBox() != nil }
            let box = try #require(resultBox())
            #expect(!toolbar.frame.intersects(box.frame))
            #expect(box.frame.maxX == screen.visibleFrame.maxX - CaptureResultBoxMetrics.edgeInset)
            #expect(box.frame.maxY == screen.visibleFrame.maxY - CaptureResultBoxMetrics.edgeInset)

            try await eventually { await fixture.http.imageRequests.count == 1 }
            try clickResultBoxButton(box, fromEnd: 0)
            try await eventually { resultBox() == nil }
            #expect(toolbar.frame.minX == originalX)
        }
    }

    @Test
    func unwritableScreenshotFolderShowsItsReasonWithoutARequest() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)
            let folder = fixture.root.appendingPathComponent("Pictures")
            try? FileManager.default.removeItem(at: folder)
            try Data().write(to: folder)

            try await clickExtract(toolbar)
            try await eventually {
                if case .failure = resultBoxPresentation()?.body { return true }
                return false
            }
            #expect(await fixture.http.imageRequests.isEmpty)
            #expect(model.historyRecords.isEmpty)
            #expect(resultBoxPresentation()?.body == .failure(
                "The screenshot could not be saved. Check disk space and folder permissions, then retry."
            ))
            try await waitForResultIdle(model)

            try FileManager.default.removeItem(at: folder)
            try clickResultBoxButton(try #require(resultBox()), fromEnd: 1)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Saved after all")
            try await eventually { model.historyRecords.first?.operation.sourceMarkdown == "Saved after all" }
        }
    }

    @Test
    func requestFailureShowsItsReasonWithoutPartialText() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickTranslate(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.streamImage(content: #"{"segments":[{"id":"s1","block":"p1","kind":"paragraph","source":"Hello","translation":"Partial text"},"#)
            try await eventually { resultBoxText() == "Partial text" }

            await fixture.http.failImage()

            try await eventually {
                resultBoxPresentation()?.body == .failure("VLMSnapper could not reach the Provider. Check the network and retry manually.")
            }
            try await eventually { resultBoxText() == nil }
            #expect(resultBoxPresentation()?.canCopy == false)
            #expect(resultBoxPresentation()?.canRetry == true)
            try await eventually { model.historyRecords.first?.operation.status == .failed }
        }
    }
}
