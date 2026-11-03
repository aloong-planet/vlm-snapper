import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

// The toolbar's icon buttons (v1-core::REQ-008, REQ-009): Copy, Save and Close. Positions come from the
// toolbar's fixed geometry — padding 3 pt, 25 pt boxes, 3 pt gaps — counted from the right end.
@Suite("Capture toolbar icon buttons", .serialized)
@MainActor
struct CaptureToolbarIconButtonTests {
    @Test("an icon button answers a press anywhere in its box, not only on the icon's strokes")
    func iconButtonsAnswerAnywhereInTheirBox() throws {
        let presses = PressLog()
        let window = try toolbarWindow(presses)
        defer { window.orderOut(nil) }
        for (index, name) in ["close", "save", "copy"].enumerated() {
            let center = boxCenter(window, fromEnd: index)
            // Inside the 25 pt box, clear of the 13 pt icon.
            try press(window, at: NSPoint(x: center.x + 10, y: center.y + 10))
            #expect(presses.names.last == name, "\(name)")
        }
        #expect(presses.names == ["close", "save", "copy"])
    }

    @Test("an operation button that is not selected answers a press in its padding")
    func unselectedOperationButtonAnswersInPadding() throws {
        let presses = PressLog()
        let state = CaptureToolbarState(targetLanguageCode: "en")
        state.currentOperation = .translate
        let window = try toolbarWindow(presses, state: state)
        defer { window.orderOut(nil) }
        // Extract is the first control: 3 pt toolbar padding, then 9 pt of the button's own padding.
        let midY = try #require(window.contentView).bounds.midY
        try press(window, at: NSPoint(x: 6, y: midY))
        #expect(presses.names == ["extract"])
    }

    @Test("the left part of the combined button translates and the right part opens the language list")
    func translateControlHasTwoParts() throws {
        let presses = PressLog()
        let window = try toolbarWindow(presses, state: CaptureToolbarState(targetLanguageCode: "zh-Hans"))
        defer { window.orderOut(nil) }
        let right = translateControlRightEdge(window)
        let midY = try #require(window.contentView).bounds.midY
        let before = popoverCount()

        try press(window, at: NSPoint(x: right - 8, y: midY))
        #expect(presses.names.isEmpty)
        try waitUntil { popoverCount() > before }
        closePopovers()

        try press(window, at: NSPoint(x: right - 70, y: midY))
        #expect(presses.names == ["translate"])
    }

    @Test("during a request only cancel, the language and the running operation take a press")
    func requestDisablesOtherActions() throws {
        let presses = PressLog()
        let state = CaptureToolbarState(targetLanguageCode: "en")
        state.currentOperation = .translate
        state.isRequestRunning = true
        let window = try toolbarWindow(presses, state: state)
        defer { window.orderOut(nil) }
        let midY = try #require(window.contentView).bounds.midY
        let right = translateControlRightEdge(window)

        try press(window, at: NSPoint(x: 8, y: midY))
        #expect(presses.names.isEmpty)
        for index in [1, 2] {
            let center = boxCenter(window, fromEnd: index)
            try press(window, at: center)
        }
        #expect(presses.names.isEmpty)

        try press(window, at: NSPoint(x: right - 70, y: midY))
        #expect(presses.names == ["translate"], "the running operation takes it; the application then ignores it")

        let before = popoverCount()
        try press(window, at: NSPoint(x: right - 8, y: midY))
        try waitUntil { popoverCount() > before }
        closePopovers()

        let cancel = boxCenter(window, fromEnd: 0)
        try press(window, at: cancel)
        #expect(presses.names == ["translate", "close"])
    }

    @Test("a row of the language list shows its abbreviation and name, and a press sets the language and closes the list")
    func languageRowSetsLanguage() throws {
        let presses = PressLog()
        let state = CaptureToolbarState(targetLanguageCode: "en")
        let window = try toolbarWindow(presses, state: state)
        defer { window.orderOut(nil) }
        defer { closePopovers() }
        let before = popoverCount()
        try press(window, at: NSPoint(x: translateControlRightEdge(window) - 8, y: try #require(window.contentView).bounds.midY))
        try waitUntil { popoverCount() > before }
        let popover = try #require(NSApp.windows.first { $0.className.contains("Popover") && $0.isVisible })
        let content = try #require(popover.contentView)
        var table: NSTableView?
        try waitUntil {
            content.layoutSubtreeIfNeeded()
            table = allSubviews(content).compactMap { $0 as? NSTableView }.first
            return (table?.numberOfRows ?? 0) == 2
        }
        let rows = try recognizedText(in: content)
        #expect(rows.contains("EN"))
        #expect(rows.contains("English"))
        #expect(rows.contains("ZH"))

        let list = try #require(table)
        let row = list.rect(ofRow: 1)
        try press(popover, at: list.convert(NSPoint(x: row.minX + 60, y: row.midY), to: nil))

        try waitUntil { state.targetLanguageCode == "zh-Hans" }
        #expect(presses.names == ["language zh-Hans"])
        try waitUntil { popoverCount() == before }
    }

    // The hint itself appears only under a real pointer: that is checked on the installed build.
    @Test("the language part's hint names the target language in full")
    func languageHintNamesLanguage() {
        LocalizationTestCoordinator.withExclusiveAccess {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
            #expect(VLMSnapperStrings.targetLanguageHint("简体中文") == "目标语言：简体中文")
        }
    }

    @Test("an operation that cannot start while a result is unsaved takes no press")
    func unavailableOperationTakesNoPress() throws {
        let presses = PressLog()
        let state = CaptureToolbarState(targetLanguageCode: "en")
        state.currentOperation = .translate
        state.unavailableOperations = [.extract]
        let window = try toolbarWindow(presses, state: state)
        defer { window.orderOut(nil) }
        let midY = try #require(window.contentView).bounds.midY

        try press(window, at: NSPoint(x: 8, y: midY))
        #expect(presses.names.isEmpty)
        try press(window, at: boxCenter(window, fromEnd: 2))
        #expect(presses.names == ["copy"])
    }

    @Test("the operation whose result box is showing looks selected, and only then")
    func currentOperationLooksSelected() throws {
        let state = CaptureToolbarState(targetLanguageCode: "en")
        let window = try toolbarWindow(PressLog(), state: state)
        defer { window.orderOut(nil) }
        let view = try #require(window.contentView)
        let point = NSPoint(x: 5, y: view.bounds.midY)
        let plain = try renderedColor(view, at: point)
        state.currentOperation = .extract
        try waitUntil { (try? renderedColor(view, at: point)) != plain }
        state.currentOperation = nil
        try waitUntil { (try? renderedColor(view, at: point)) == plain }

        // Above the labels, in both parts of the combined button.
        let right = translateControlRightEdge(window)
        let translatePart = NSPoint(x: right - 70, y: view.bounds.midY + 10)
        let languagePart = NSPoint(x: right - 4, y: view.bounds.midY + 10)
        let plainTranslate = try renderedColor(view, at: translatePart)
        let plainLanguage = try renderedColor(view, at: languagePart)
        state.currentOperation = .translate
        try waitUntil { (try? renderedColor(view, at: translatePart)) != plainTranslate }
        try waitUntil { (try? renderedColor(view, at: languagePart)) != plainLanguage }
        #expect(try renderedColor(view, at: point) == plain, "Extract does not look selected with it")
        state.currentOperation = .extract
        try waitUntil { (try? renderedColor(view, at: translatePart)) == plainTranslate }
        try waitUntil { (try? renderedColor(view, at: languagePart)) == plainLanguage }
    }

    @Test("the language part grows with the abbreviation, and the toolbar shows no Provider or model")
    func languagePartFollowsAbbreviation() throws {
        let short = NSHostingView(rootView: toolbar(state: CaptureToolbarState(targetLanguageCode: "zh-Hans"), presses: PressLog()))
        let long = NSHostingView(rootView: toolbar(state: CaptureToolbarState(targetLanguageCode: "aeb"), presses: PressLog()))
        let growth = long.fittingSize.width - short.fittingSize.width
        #expect(growth > 0 && growth < 15, "growth \(growth)")
        // Extract, Translate and the abbreviation with its chevron, then Copy, Save and Close, without a model label.
        #expect(short.fittingSize.width < 300, "width \(short.fittingSize.width)")
    }

    // The Copy symbol is 13 pt wide and 16 pt tall at the toolbar's 13 pt symbol size; a square is
    // 11.5 pt (measured 2026-10-29). The floppy disk matches Copy's width so the two read as one size.
    // Rendered at a fixed 2 px per point, and the outline's anti-aliased edge counts as ink, so the result
    // does not depend on the machine's display scale or how its renderer shades a thin stroke's edge
    // (CI measured the 1.2 pt outline 2 pt narrower than this Mac when only dark pixels counted).
    @Test("the save icon is a square as wide as the copy icon next to it")
    func saveIconMatchesCopyIconWidth() throws {
        let window = try toolbarWindow(PressLog())
        defer { window.orderOut(nil) }
        let view = try #require(window.contentView)
        let scale: CGFloat = 2
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * scale), pixelsHigh: Int(view.bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        representation.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: representation)
        let copy = try inkBounds(representation, view: view, box: boxRect(window, fromEnd: 2))
        let save = try inkBounds(representation, view: view, box: boxRect(window, fromEnd: 1))
        #expect(abs(save.width - copy.width) <= 1, "save \(save) copy \(copy)")
        #expect(abs(save.height - save.width) <= 1, "save \(save)")
    }
}

@MainActor
private final class PressLog {
    var names: [String] = []
}

@MainActor
private func toolbar(state: CaptureToolbarState, presses: PressLog) -> CaptureOperationToolbar {
    CaptureOperationToolbar(
        state: state,
        targetLanguages: [
            TargetLanguageOption(code: "en", name: "English"),
            TargetLanguageOption(code: "zh-Hans", name: "简体中文"),
        ],
        onStart: { presses.names.append($0 == .extract ? "extract" : "translate") },
        onTargetLanguageChange: { presses.names.append("language \($0)") },
        onCopy: { presses.names.append("copy") },
        onSave: { presses.names.append("save") },
        onCancel: { presses.names.append("close") }
    )
}

/// The combined button's right edge: padding, three icon boxes, their gaps, the 1 pt divider and its gaps.
@MainActor
private func translateControlRightEdge(_ window: NSWindow) -> CGFloat {
    let bounds = window.contentView?.bounds ?? .zero
    let size = VLMSnapperUIConstants.toolbarControlHeight
    let gap = VLMSnapperUIConstants.toolbarControlGap
    return bounds.maxX - VLMSnapperUIConstants.toolbarPadding - 3 * size - 3 * gap - 1 - gap
}

@MainActor
private func closePopovers() {
    for popover in NSApp.windows where popover.className.contains("Popover") && popover.isVisible {
        popover.orderOut(nil)
    }
}

@MainActor
private func allSubviews(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(allSubviews)
}

@MainActor
private func popoverCount() -> Int {
    NSApp.windows.filter { $0.className.contains("Popover") && $0.isVisible }.count
}

@MainActor
private func waitUntil(_ condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(2)
    while !condition(), Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    try #require(condition())
}

@MainActor
private func renderedColor(_ view: NSView, at point: NSPoint) throws -> [CGFloat] {
    view.layoutSubtreeIfNeeded()
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    let scale = CGFloat(representation.pixelsWide) / view.bounds.width
    let color = try #require(representation.colorAt(
        x: Int(point.x * scale),
        y: Int((view.bounds.height - point.y) * scale)
    )?.usingColorSpace(.sRGB))
    return [color.redComponent, color.greenComponent, color.blueComponent]
}

@MainActor
private func toolbarWindow(
    _ presses: PressLog,
    state: CaptureToolbarState = CaptureToolbarState(targetLanguageCode: "en")
) throws -> NSWindow {
    let hosting = NSHostingView(rootView: toolbar(state: state, presses: presses))
    hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    window.appearance = NSAppearance(named: .aqua)
    window.orderFrontRegardless()
    hosting.layoutSubtreeIfNeeded()
    return window
}

@MainActor
private func boxRect(_ window: NSWindow, fromEnd index: Int) -> CGRect {
    let bounds = window.contentView?.bounds ?? .zero
    let size = VLMSnapperUIConstants.toolbarControlHeight
    let maxX = bounds.maxX - VLMSnapperUIConstants.toolbarPadding
        - CGFloat(index) * (size + VLMSnapperUIConstants.toolbarControlGap)
    return CGRect(x: maxX - size, y: bounds.midY - size / 2, width: size, height: size)
}

@MainActor
private func boxCenter(_ window: NSWindow, fromEnd index: Int) -> NSPoint {
    let box = boxRect(window, fromEnd: index)
    return NSPoint(x: box.midX, y: box.midY)
}

@MainActor
private func press(_ window: NSWindow, at point: NSPoint) throws {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        window.sendEvent(try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1
        )))
    }
}

/// Bounds, in points, of the icon pixels inside a box of the rendered toolbar (light appearance): any pixel
/// clearly darker than the light background, so an outline's anti-aliased edge counts.
@MainActor
private func inkBounds(_ representation: NSBitmapImageRep, view: NSView, box: CGRect) throws -> CGRect {
    let scale = CGFloat(representation.pixelsWide) / view.bounds.width
    var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
    // Bitmap rows count from the top.
    let rows = Int((view.bounds.height - box.maxY) * scale)..<Int((view.bounds.height - box.minY) * scale)
    let columns = Int(box.minX * scale)..<Int(box.maxX * scale)
    for y in rows {
        for x in columns {
            guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                  color.alphaComponent > 0.5,
                  (color.redComponent + color.greenComponent + color.blueComponent) / 3 < 0.8 else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    try #require(minX <= maxX, "no icon pixels in \(box)")
    return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                  width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
}

