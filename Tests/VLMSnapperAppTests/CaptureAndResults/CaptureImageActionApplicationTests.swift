import AppKit
import Foundation
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

extension ProviderApplicationTests {
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

    @Test("a cancelled save keeps the selection, and a double click on Save opens one panel", arguments: [1, 2])
    func cancelledSaveKeepsTheSelectionAndOneActionRuns(clicks: Int) async throws {
        try await withSnapFixture { fixture, _, _ in
            fixture.imageSaver.answer = .cancel
            let toolbar = try await selectWindow(fixture)
            let save = try toolbarIconCenter(toolbar, fromEnd: 1)
            for _ in 0..<clicks {
                try click(toolbar, at: save)
            }
            try await eventually { !fixture.imageSaver.requests.isEmpty }
            pumpNativeEvents(toolbar)
            #expect(try mainScreenOverlay() != nil)
            #expect(captureToolbar() != nil)
            // Copy runs after every click was handled; the cancelled panel leaves Copy usable.
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
}
