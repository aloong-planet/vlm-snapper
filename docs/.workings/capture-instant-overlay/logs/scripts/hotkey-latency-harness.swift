import AppKit
import CoreMedia
import QuartzCore
import ScreenCaptureKit

// Posts the app's capture shortcut and reports, from the composited screen, when the
// overlay first shows and when it first covers every sampled point including the edges.
final class Recorder: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [(Double, [Double])] = []
    func snapshot() -> [(Double, [Double])] { lock.withLock { frames } }
    func reset() { lock.withLock { frames.removeAll() } }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sample.imageBuffer else { return }
        if let a = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = a.first?[.status] as? Int, SCFrameStatus(rawValue: raw) != .complete { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        var values: [Double] = []
        let xs = [1] + stride(from: w / 20, to: w - 1, by: w / 20).map { $0 } + [w - 2]
        let ys = [1] + stride(from: h / 12, to: h - 1, by: h / 12).map { $0 } + [h - 2]
        for y in ys { for x in xs { let p = base + y * row + x * 4
            values.append(0.0722 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.2126 * Double(p[2])) } }
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        lock.withLock { frames.append((t, values)) }
    }
}
func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
    for down in [true, false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!; e.flags = flags; e.post(tap: .cghidEventTap) }
}
@MainActor
func run() async {
    let rounds = Int(CommandLine.arguments[1]) ?? 3
    let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let display = content.displays.first { $0.displayID == CGMainDisplayID() }!
    let config = SCStreamConfiguration()
    config.width = display.width / 2; config.height = display.height / 2
    config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    config.pixelFormat = kCVPixelFormatType_32BGRA; config.showsCursor = false
    let recorder = Recorder()
    let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: nil)
    try! stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "rec"))
    try! await stream.startCapture()
    for round in 0..<rounds {
        try? await Task.sleep(for: .milliseconds(1200))
        let baseline = recorder.snapshot().last!.1
        recorder.reset()
        let start = CACurrentMediaTime()
        postKey(3, flags: [.maskCommand, .maskShift])
        try? await Task.sleep(for: .milliseconds(1000))
        postKey(53, flags: [])
        var first: Double?, full: Double?, partial = 0
        for (t, v) in recorder.snapshot() where t >= start {
            let pairs = zip(v, baseline).filter { $0.1 > 60 }
            let dimmed = pairs.filter { $0.0 < $0.1 * 0.75 }.count
            if dimmed > 0, first == nil { first = (t - start) * 1000 }
            if dimmed == pairs.count, full == nil { full = (t - start) * 1000 }
            if dimmed > 0, dimmed < pairs.count, full == nil { partial += 1 }
        }
        print(String(format: "round %d: first overlay frame %@ ms, full coverage %@ ms, partial frames before full %d", round,
            first.map { String(format: "%.0f", $0) } ?? "none", full.map { String(format: "%.0f", $0) } ?? "none", partial))
    }
    try? await stream.stopCapture()
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in await run() }
app.run()
