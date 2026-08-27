import Foundation

public protocol ScreenCapturePermissionChecking: Sendable {
    func hasScreenCaptureAccess() -> Bool
}

public enum CaptureDiscoveryError: Error, Equatable, Sendable {
    case permissionDenied
    case discoveryFailed
}

public enum DisplayCaptureFailureReason: Equatable, Sendable {
    case captureFailed
    case displayDisconnected
    case geometryChanged
}

public struct DisplayCaptureFailure: Equatable, Sendable {
    public let displayID: UInt32
    public let reason: DisplayCaptureFailureReason

    public init(
        displayID: UInt32,
        reason: DisplayCaptureFailureReason
    ) {
        self.displayID = displayID
        self.reason = reason
    }
}

public struct FrozenDisplayBatch: Sendable {
    public let displays: [FrozenCaptureDisplay]
    public let failures: [DisplayCaptureFailure]

    public init(
        displays: [FrozenCaptureDisplay] = [],
        failures: [DisplayCaptureFailure] = []
    ) {
        self.displays = displays
        self.failures = failures
    }
}

public protocol FrozenDisplayCapturing: Sendable {
    func captureFrozenDisplays() async throws(CaptureDiscoveryError) -> FrozenDisplayBatch
}

public enum CaptureFreezeResult: Sendable {
    case ready(
        session: CaptureSelectionSession,
        frozenDisplays: [FrozenCaptureDisplay],
        failedDisplays: [DisplayCaptureFailure]
    )
    case permissionRequired
    case allDisplaysFailed([DisplayCaptureFailure])
}

public struct CaptureFreezeCoordinator: Sendable {
    private let permissionChecker: any ScreenCapturePermissionChecking
    private let capturer: any FrozenDisplayCapturing
    private let cropper: any CaptureImageCropping

    public init(
        permissionChecker: any ScreenCapturePermissionChecking,
        capturer: any FrozenDisplayCapturing,
        cropper: any CaptureImageCropping
    ) {
        self.permissionChecker = permissionChecker
        self.capturer = capturer
        self.cropper = cropper
    }

    public func startCapture() async -> CaptureFreezeResult {
        guard permissionChecker.hasScreenCaptureAccess() else {
            return .permissionRequired
        }
        let batch: FrozenDisplayBatch
        do {
            batch = try await capturer.captureFrozenDisplays()
        } catch let error {
            switch error {
            case .permissionDenied:
                return .permissionRequired
            case .discoveryFailed:
                return .allDisplaysFailed([])
            }
        }
        guard !batch.displays.isEmpty else {
            return .allDisplaysFailed(batch.failures)
        }
        return .ready(
            session: CaptureSelectionSession(
                displays: batch.displays,
                cropper: cropper
            ),
            frozenDisplays: batch.displays,
            failedDisplays: batch.failures
        )
    }
}
