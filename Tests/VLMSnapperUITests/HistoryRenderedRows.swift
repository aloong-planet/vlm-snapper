import AppKit

// SwiftUI's virtual rows are not exported through the in-process accessibility
// tree in this runner. Inspect visible pixels instead of private view classes.
// Fixtures fit the viewport. This is a rendering gate, not VoiceOver acceptance.
@MainActor
struct HistoryRenderedRow {
    let scroll: NSScrollView
    let root: NSView
    let pixelsX: Range<Int>
    let inkY: Int
    let bitmap: NSBitmapImageRep

    func screenFrame() -> NSRect {
        let scale = CGFloat(bitmap.pixelsHigh) / root.bounds.height
        let y = root.isFlipped ? CGFloat(inkY) / scale : root.bounds.height - CGFloat(inkY) / scale
        let x = CGFloat(pixelsX.lowerBound) / scale + 30
        let point = root.convert(NSPoint(x: x, y: y), to: nil)
        return scroll.window?.convertToScreen(NSRect(x: point.x, y: point.y, width: 1, height: 1)) ?? .zero
    }

    func isSelected() -> Bool {
        let dark = scroll.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let expected: [CGFloat] = dark ? [49, 67, 97] : [220, 230, 245]
        return pixelsX.contains { pixelMatches(bitmap, x: $0, y: inkY, rgb: expected) }
    }
}

@MainActor
private func pixelMatches(_ bitmap: NSBitmapImageRep, x: Int, y: Int, rgb: [CGFloat]) -> Bool {
    // The bitmap has already been converted to sRGB. colorAt returns those
    // component values in a calibrated-color wrapper; converting it again
    // changes the values (verified against the PNG's embedded profile).
    guard let color = bitmap.colorAt(x: x, y: y) else { return false }
    return zip([color.redComponent, color.greenComponent, color.blueComponent], rgb)
        .allSatisfy { abs($0 - $1 / 255) < 0.015 }
}

@MainActor
func historyRenderedRows(in root: NSView) -> [HistoryRenderedRow] {
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    guard let scroll = descendants(root).compactMap({ $0 as? NSScrollView })
        .first(where: { abs($0.frame.width - 260) < 2 }),
          let captured = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return [] }
    // SwiftUI paints into the hosting root; caching the child NSScrollView
    // alone produces a blank surface rather than the composited row pixels.
    root.cacheDisplay(in: root.bounds, to: captured)
    guard let png = captured.representation(using: .png, properties: [:]),
          let decoded = NSBitmapImageRep(data: png),
          let bitmap = decoded.converting(to: .sRGB, renderingIntent: .default) else { return [] }
    let rect = scroll.convert(scroll.bounds, to: root)
    let scale = CGFloat(bitmap.pixelsWide) / root.bounds.width
    let xs = max(0, Int(rect.minX * scale))..<min(bitmap.pixelsWide, Int(rect.maxX * scale))
    let top = root.isFlipped ? rect.minY : root.bounds.height - rect.maxY
    let ys = max(0, Int(top * scale))..<min(bitmap.pixelsHigh, Int((top + rect.height) * scale))
    let dark = scroll.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let blue: [CGFloat] = dark ? [155, 192, 255] : [21, 83, 178]
    var bands: [[Int]] = []
    for y in ys {
        // Only operation-kind labels use this exact blue in the record pane.
        if (xs.lowerBound..<min(xs.upperBound, xs.lowerBound + 180)).contains(where: { pixelMatches(bitmap, x: $0, y: y, rgb: blue) }) {
            if let previous = bands.last?.last, y - previous <= 3 { bands[bands.count - 1].append(y) }
            else { bands.append([y]) }
        }
    }
    return bands.map { HistoryRenderedRow(scroll: scroll, root: root, pixelsX: xs, inkY: $0[$0.count / 2], bitmap: bitmap) }
}

@MainActor
func historySelectedWidth(in row: HistoryRenderedRow) -> CGFloat {
    let bitmap = row.bitmap
    let dark = row.scroll.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let rgb: [CGFloat] = dark ? [49, 67, 97] : [220, 230, 245]
    let pixels = row.pixelsX.filter { pixelMatches(bitmap, x: $0, y: row.inkY, rgb: rgb) }
    guard let first = pixels.first, let last = pixels.last else { return 0 }
    return CGFloat(last - first + 1) * row.root.bounds.width / CGFloat(bitmap.pixelsWide)
}
