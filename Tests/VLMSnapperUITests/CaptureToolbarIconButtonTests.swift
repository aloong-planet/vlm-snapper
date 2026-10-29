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
        let window = try toolbarWindow(presses, operation: .translate)
        defer { window.orderOut(nil) }
        // Extract is the first control: 3 pt toolbar padding, then 9 pt of the button's own padding.
        let midY = try #require(window.contentView).bounds.midY
        try press(window, at: NSPoint(x: 6, y: midY))
        #expect(presses.names == ["extract"])
    }

    // The Copy symbol is 13 pt wide and 16 pt tall at the toolbar's 13 pt symbol size; a square is
    // 11.5 pt (measured 2026-10-29). The floppy disk matches Copy's width so the two read as one size.
    @Test("the save icon is a square as wide as the copy icon next to it")
    func saveIconMatchesCopyIconWidth() throws {
        let window = try toolbarWindow(PressLog())
        defer { window.orderOut(nil) }
        let view = try #require(window.contentView)
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let copy = try inkBounds(representation, view: view, box: boxRect(window, fromEnd: 2))
        let save = try inkBounds(representation, view: view, box: boxRect(window, fromEnd: 1))
        #expect(abs(save.width - copy.width) <= 0.5, "save \(save) copy \(copy)")
        #expect(abs(save.height - save.width) <= 0.5, "save \(save)")
    }
}

@MainActor
private final class PressLog {
    var names: [String] = []
}

@MainActor
private func toolbarWindow(
    _ presses: PressLog,
    operation selected: WorkspaceOperationKind = .extract
) throws -> NSWindow {
    var operation = selected
    var language = "en"
    let toolbar = CaptureOperationToolbar(
        operation: Binding(get: { operation }, set: { operation = $0 }),
        targetLanguageCode: Binding(get: { language }, set: { language = $0 }),
        targetLanguages: [TargetLanguageOption(code: "en", name: "English")],
        providerSummary: "DeepSeek · deepseek-v4-flash",
        onStart: { presses.names.append($0 == .extract ? "extract" : "translate") },
        onCopy: { presses.names.append("copy") },
        onSave: { presses.names.append("save") },
        onCancel: { presses.names.append("close") }
    )
    let hosting = NSHostingView(rootView: toolbar)
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

/// Bounds, in points, of the dark icon pixels inside a box of the rendered toolbar (light appearance).
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
                  (color.redComponent + color.greenComponent + color.blueComponent) / 3 < 0.5 else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    try #require(minX <= maxX, "no icon pixels in \(box)")
    return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                  width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
}

