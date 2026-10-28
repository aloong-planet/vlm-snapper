import AppKit
import ScreenCaptureKit

// Drives the installed VLMSnapper: shortcut, real pointer moves, composited screenshots.
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
    for down in [true, false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!; e.flags = flags; e.post(tap: .cghidEventTap) }
}
func luma(_ img: CGImage, _ p: CGPoint, scale: CGFloat) -> Double {
    let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: -p.x * scale, y: -(CGFloat(img.height) - p.y * scale), width: CGFloat(img.width), height: CGFloat(img.height)))
    let d = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return 0.2126 * Double(d[0]) + 0.7152 * Double(d[1]) + 0.0722 * Double(d[2])
}
@MainActor func shot(_ display: SCDisplay) async -> CGImage {
    let cfg = SCStreamConfiguration(); cfg.width = display.width * 2; cfg.height = display.height * 2; cfg.showsCursor = false
    return try! await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
}
@MainActor func run() async {
    let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let display = content.displays.first { $0.displayID == CGMainDisplayID() }!
    let vsnap = NSRunningApplication.runningApplications(withBundleIdentifier: "com.loong.vlmsnapper").first!.processIdentifier
    let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first!.processIdentifier
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
    func bounds(_ w: [String: Any]) -> CGRect { CGRect(dictionaryRepresentation: w[kCGWindowBounds as String] as! CFDictionary)! }
    let me = ProcessInfo.processInfo.processIdentifier
    let window = list.first { ($0[kCGWindowLayer as String] as! Int) == 0 && ($0[kCGWindowOwnerPID as String] as! Int32) != vsnap && ($0[kCGWindowOwnerPID as String] as! Int32) != me && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 && bounds($0).width > 200 }!
    let status = list.first { ($0[kCGWindowLayer as String] as! Int) == 25 && bounds($0).width > 20 }!
    let wb = bounds(window), sb = bounds(status)
    print("target window \(window[kCGWindowOwnerName as String] ?? "?") \(wb); status item \(sb); dock pid \(dock)")
    let baseline = await shot(display)
    let s = CGFloat(baseline.width) / CGFloat(display.width)
    key(3, [.maskCommand, .maskShift]); try? await Task.sleep(for: .milliseconds(700))
    let probes: [(String, CGPoint, CGPoint, CGPoint)] = [
        ("window", CGPoint(x: wb.midX, y: wb.midY), CGPoint(x: wb.midX + wb.width / 4, y: wb.midY), CGPoint(x: 300, y: 12)),
        ("status item", CGPoint(x: sb.midX, y: sb.midY), CGPoint(x: sb.midX, y: sb.midY), CGPoint(x: 300, y: 12)),
        ("dock strip", CGPoint(x: CGFloat(display.width) / 2, y: CGFloat(display.height) - 20), CGPoint(x: 40, y: CGFloat(display.height) - 8), CGPoint(x: CGFloat(display.width) / 2, y: 500)),
    ]
    for (name, pointer, inside, outside) in probes {
        post(.mouseMoved, pointer); try? await Task.sleep(for: .milliseconds(250))
        let img = await shot(display)
        let ri = luma(img, inside, scale: s) / max(1, luma(baseline, inside, scale: s)), ro = luma(img, outside, scale: s) / max(1, luma(baseline, outside, scale: s))
        print(String(format: "%@: inside %.2f of baseline, outside %.2f of baseline -> %@", name, ri, ro, (ri > 0.85 && ro < 0.7) ? "PASS" : "CHECK"))
    }
    post(.mouseMoved, CGPoint(x: wb.midX, y: wb.midY)); try? await Task.sleep(for: .milliseconds(200))
    post(.leftMouseDown, CGPoint(x: wb.midX, y: wb.midY)); post(.leftMouseUp, CGPoint(x: wb.midX, y: wb.midY)); try? await Task.sleep(for: .milliseconds(700))
    let after = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    let toolbar = after.first { ($0[kCGWindowOwnerPID as String] as! Int32) == vsnap && ($0[kCGWindowLayer as String] as! Int) > 1000 }
    print("toolbar after click: \(toolbar.map { "\(bounds($0))" } ?? "none") (window minX \(wb.minX), maxY \(wb.maxY))")
    key(53, []); try? await Task.sleep(for: .milliseconds(300)); key(53, [])
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in await run() }
app.run()
