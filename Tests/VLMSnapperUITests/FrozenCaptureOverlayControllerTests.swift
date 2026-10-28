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

        #expect(present(controller))
        #expect(controller.commit(displays: [makeDisplay(id: displayID, screen: screen)]))
        let currentDisplayIDs = controller.presentedDisplayIDs
        let current = visibleOverlays()
        #expect(!current.isEmpty)

        #expect(present(controller))
        let pending = visibleOverlays()
        #expect(!pending.isEmpty)
        #expect(current.allSatisfy { !$0.isVisible })
        let failedReplacement = controller.commit(displays: [])
        #expect(!failedReplacement)
        controller.rollback()

        #expect(controller.presentedDisplayIDs == currentDisplayIDs)
        #expect(current.allSatisfy { $0.isVisible && $0.contentView != nil })
        #expect(pending.allSatisfy { !$0.isVisible })
    }

    // The open animation scales only the composited window: frame and window-server
    // bounds already equal the screen, so the window's behavior is the observable here.
    @Test("the pending overlay covers each display without an opening animation")
    func pendingOverlayAppearsWithoutOpeningAnimation() {
        let controller = FrozenCaptureOverlayController()
        defer { controller.close() }

        #expect(present(controller))

        let overlays = visibleOverlays()
        #expect(!overlays.isEmpty)
        #expect(overlays.allSatisfy { $0.animationBehavior == .none })
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
        #expect(present(controller))
        #expect(controller.commit(displays: [makeDisplay(id: displayID, screen: screen)]))
        let alert = NSAlert()

        controller.prepareFailurePresentation(alert)

        #expect(alert.window.level.rawValue > NSWindow.Level.screenSaver.rawValue)
    }
}

@MainActor
private func visibleOverlays() -> [NSWindow] {
    NSApp.windows.filter { $0.isVisible && $0.level == .screenSaver }
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

@MainActor
private func present(_ controller: FrozenCaptureOverlayController) -> Bool {
    controller.presentPending(onSelection: { _ in }, onCancel: {})
}
