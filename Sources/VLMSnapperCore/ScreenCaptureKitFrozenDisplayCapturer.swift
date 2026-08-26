import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

public struct CoreGraphicsScreenCapturePermissionChecker:
    ScreenCapturePermissionChecking
{
    public init() {}

    public func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

public struct ScreenCaptureKitFrozenDisplayCapturer: FrozenDisplayCapturing {
    public init() {}

    public func captureFrozenDisplays() async throws(CaptureDiscoveryError)
        -> FrozenDisplayBatch
    {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            if isPermissionDenied(error) {
                throw .permissionDenied
            }
            throw .discoveryFailed
        }

        let attempts = await withTaskGroup(
            of: NativeDisplayCaptureAttempt.self,
            returning: [NativeDisplayCaptureAttempt].self
        ) { group in
            for display in content.displays {
                group.addTask {
                    await capture(display: display)
                }
            }
            var results: [NativeDisplayCaptureAttempt] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        if attempts.contains(where: { $0.permissionDenied }) {
            throw .permissionDenied
        }
        let displays = attempts.compactMap(\.display).sorted {
            $0.geometry.displayID < $1.geometry.displayID
        }
        let failures = attempts.compactMap(\.failure).sorted {
            $0.displayID < $1.displayID
        }
        return FrozenDisplayBatch(displays: displays, failures: failures)
    }
}

private struct NativeDisplayCaptureAttempt: Sendable {
    let display: FrozenCaptureDisplay?
    let failure: DisplayCaptureFailure?
    let permissionDenied: Bool
}

private func capture(display: SCDisplay) async -> NativeDisplayCaptureAttempt {
    let displayID = display.displayID
    guard let initialGeometry = currentGeometry(for: displayID) else {
        return failedAttempt(displayID: displayID, reason: .displayDisconnected)
    }

    let configuration = SCStreamConfiguration()
    configuration.width = initialGeometry.pixelWidth
    configuration.height = initialGeometry.pixelHeight
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = false
    configuration.scalesToFit = false
    configuration.preservesAspectRatio = true
    configuration.colorSpaceName = CGColorSpace.sRGB
    configuration.captureResolution = .best

    let filter = SCContentFilter(display: display, excludingWindows: [])
    do {
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        guard let finalGeometry = currentGeometry(for: displayID) else {
            return failedAttempt(displayID: displayID, reason: .displayDisconnected)
        }
        guard finalGeometry == initialGeometry else {
            return failedAttempt(displayID: displayID, reason: .geometryChanged)
        }
        guard image.width == initialGeometry.pixelWidth,
              image.height == initialGeometry.pixelHeight
        else {
            return failedAttempt(displayID: displayID, reason: .captureFailed)
        }
        return NativeDisplayCaptureAttempt(
            display: FrozenCaptureDisplay(
                geometry: initialGeometry,
                frame: FrozenDisplayFrame(image: image)
            ),
            failure: nil,
            permissionDenied: false
        )
    } catch {
        if isPermissionDenied(error) {
            return NativeDisplayCaptureAttempt(
                display: nil,
                failure: nil,
                permissionDenied: true
            )
        }
        let reason: DisplayCaptureFailureReason =
            CGDisplayIsActive(displayID) == 0
            ? .displayDisconnected
            : .captureFailed
        return failedAttempt(displayID: displayID, reason: reason)
    }
}

private func currentGeometry(
    for displayID: CGDirectDisplayID
) -> CaptureDisplayGeometry? {
    guard CGDisplayIsActive(displayID) != 0 else {
        return nil
    }
    let pixelWidth = Int(CGDisplayPixelsWide(displayID))
    let pixelHeight = Int(CGDisplayPixelsHigh(displayID))
    guard pixelWidth > 0, pixelHeight > 0 else {
        return nil
    }
    let bounds = CGDisplayBounds(displayID)
    return CaptureDisplayGeometry(
        displayID: displayID,
        logicalX: bounds.origin.x,
        logicalY: bounds.origin.y,
        logicalWidth: bounds.width,
        logicalHeight: bounds.height,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        rotationDegrees: CGDisplayRotation(displayID)
    )
}

private func failedAttempt(
    displayID: UInt32,
    reason: DisplayCaptureFailureReason
) -> NativeDisplayCaptureAttempt {
    NativeDisplayCaptureAttempt(
        display: nil,
        failure: DisplayCaptureFailure(displayID: displayID, reason: reason),
        permissionDenied: false
    )
}

private func isPermissionDenied(_ error: Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == SCStreamErrorDomain
        && nsError.code == SCStreamError.Code.userDeclined.rawValue
}
