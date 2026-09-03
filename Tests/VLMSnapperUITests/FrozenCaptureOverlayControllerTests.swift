import AppKit
import CoreGraphics
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Frozen capture overlay", .serialized)
@MainActor
struct FrozenCaptureOverlayControllerTests {
    @Test("a replacement that cannot cover a display keeps the current overlay")
    func failedReplacementKeepsCurrentOverlay() throws {
        let screen = try #require(NSScreen.screens.first)
        let displayID = try #require(
            (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value
        )
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }

        let initialPresentation = controller.replace(
            displays: [makeDisplay(id: displayID, screen: screen)],
            onSelection: { _ in },
            onCancel: {}
        )
        #expect(initialPresentation)
        let currentDisplayIDs = controller.presentedDisplayIDs

        let failedReplacement = controller.replace(
            displays: [],
            onSelection: { _ in },
            onCancel: {}
        )
        #expect(!failedReplacement)
        #expect(controller.presentedDisplayIDs == currentDisplayIDs)
    }

    @Test("a failure alert stays visible above a retained overlay")
    func failureAlertStaysAboveRetainedOverlay() throws {
        let screen = try #require(NSScreen.screens.first)
        let displayID = try #require(
            (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value
        )
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }
        let initialPresentation = controller.replace(
            displays: [makeDisplay(id: displayID, screen: screen)],
            onSelection: { _ in },
            onCancel: {}
        )
        #expect(initialPresentation)
        let alert = NSAlert()

        controller.prepareFailurePresentation(alert)

        #expect(alert.window.level.rawValue > NSWindow.Level.screenSaver.rawValue)
    }
}

private func makeDisplay(
    id: UInt32,
    screen: NSScreen
) -> FrozenCaptureDisplay {
    let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return FrozenCaptureDisplay(
        geometry: CaptureDisplayGeometry(
            displayID: id,
            logicalX: screen.frame.minX,
            logicalY: screen.frame.minY,
            logicalWidth: screen.frame.width,
            logicalHeight: screen.frame.height,
            pixelWidth: 2,
            pixelHeight: 2,
            rotationDegrees: 0
        ),
        frame: FrozenDisplayFrame(image: context.makeImage()!)
    )
}
