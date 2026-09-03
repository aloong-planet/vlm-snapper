import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

public struct CoreGraphicsScreenCapturePermissionChecker:
    ScreenCapturePermissionChecking, ScreenCapturePermissionAuthorizing
{
    public init() {}

    public func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func preflightScreenCaptureAccess() async -> Bool {
        hasScreenCaptureAccess()
    }

    public func requestScreenCaptureAuthorization() async -> Bool {
        requestScreenCaptureAccess()
    }
}

public struct ScreenCaptureKitFrozenDisplayCapturer: FrozenDisplayCapturing {
    public init() {}

    public func captureFrozenDisplays() async throws(CaptureDiscoveryError)
        -> FrozenDisplayBatch
    {
        let snapshot: CurrentProcessCaptureSnapshot
        do {
            snapshot = try await currentProcessCaptureSnapshot()
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
            for display in snapshot.displays {
                group.addTask {
                    await capture(
                        display: display,
                        excluding: snapshot.currentApplication
                    )
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

private struct CurrentProcessCaptureSnapshot {
    let displays: [SCDisplay]
    let currentApplication: SCRunningApplication
}

private func currentProcessCaptureSnapshot() async throws
    -> CurrentProcessCaptureSnapshot
{
    let processID = ProcessInfo.processInfo.processIdentifier
    if let content = try? await SCShareableContent.currentProcess,
       let application = content.applications.first(where: {
           $0.processID == processID
       }), !content.displays.isEmpty {
        return CurrentProcessCaptureSnapshot(
            displays: content.displays,
            currentApplication: application
        )
    }

    let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
    )
    guard let application = content.applications.first(where: {
        $0.processID == processID
    }), !content.displays.isEmpty else {
        throw CaptureDiscoveryError.discoveryFailed
    }
    return CurrentProcessCaptureSnapshot(
        displays: content.displays,
        currentApplication: application
    )
}

private struct NativeDisplayCaptureAttempt: Sendable {
    let display: FrozenCaptureDisplay?
    let failure: DisplayCaptureFailure?
    let permissionDenied: Bool
}

struct CaptureRasterSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

func captureRasterSize(
    contentRect: CGRect,
    pointPixelScale: Float
) -> CaptureRasterSize? {
    let scaledWidth = Double(contentRect.width) * Double(pointPixelScale)
    let scaledHeight = Double(contentRect.height) * Double(pointPixelScale)
    guard scaledWidth.isFinite,
          scaledHeight.isFinite,
          scaledWidth > 0,
          scaledHeight > 0
    else {
        return nil
    }
    let roundedWidth = scaledWidth.rounded()
    let roundedHeight = scaledHeight.rounded()
    guard roundedWidth >= 1,
          roundedHeight >= 1,
          roundedWidth < Double(Int.max),
          roundedHeight < Double(Int.max)
    else {
        return nil
    }
    return CaptureRasterSize(
        width: Int(roundedWidth),
        height: Int(roundedHeight)
    )
}

private func capture(
    display: SCDisplay,
    excluding currentApplication: SCRunningApplication
) async -> NativeDisplayCaptureAttempt {
    let displayID = display.displayID
    let filter = SCContentFilter(
        display: display,
        excludingApplications: [currentApplication],
        exceptingWindows: []
    )
    guard let captureSize = captureRasterSize(
        contentRect: filter.contentRect,
        pointPixelScale: filter.pointPixelScale
    ) else {
        return failedAttempt(displayID: displayID, reason: .captureFailed)
    }
    guard let initialGeometry = currentCaptureDisplayGeometry(
        for: displayID,
        pointPixelScale: filter.pointPixelScale
    ) else {
        return failedAttempt(displayID: displayID, reason: .displayDisconnected)
    }
    guard initialGeometry.pixelWidth == captureSize.width,
          initialGeometry.pixelHeight == captureSize.height
    else {
        return failedAttempt(displayID: displayID, reason: .geometryChanged)
    }

    let configuration = SCStreamConfiguration()
    configuration.width = captureSize.width
    configuration.height = captureSize.height
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = false
    configuration.scalesToFit = false
    configuration.preservesAspectRatio = true
    configuration.colorSpaceName = CGColorSpace.sRGB
    configuration.captureResolution = .best

    do {
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        guard let finalGeometry = currentCaptureDisplayGeometry(
            for: displayID,
            pointPixelScale: filter.pointPixelScale
        ) else {
            return failedAttempt(displayID: displayID, reason: .displayDisconnected)
        }
        guard finalGeometry == initialGeometry else {
            return failedAttempt(displayID: displayID, reason: .geometryChanged)
        }
        guard image.width == captureSize.width,
              image.height == captureSize.height
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

public func currentCaptureDisplayGeometry(
    for displayID: CGDirectDisplayID,
    pointPixelScale: Float
) -> CaptureDisplayGeometry? {
    guard CGDisplayIsActive(displayID) != 0 else {
        return nil
    }
    let bounds = CGDisplayBounds(displayID)
    guard let rasterSize = captureRasterSize(
        contentRect: bounds,
        pointPixelScale: pointPixelScale
    ) else {
        return nil
    }
    return CaptureDisplayGeometry(
        displayID: displayID,
        logicalX: bounds.origin.x,
        logicalY: bounds.origin.y,
        logicalWidth: bounds.width,
        logicalHeight: bounds.height,
        pixelWidth: rasterSize.width,
        pixelHeight: rasterSize.height,
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
