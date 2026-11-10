import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Capture freeze coordinator")
struct CaptureFreezeCoordinatorTests {
    @Test("missing permission is recovered separately and capture is not attempted")
    func missingPermissionSkipsCapture() async {
        let capturer = FrozenDisplayCapturerProbe(result: .success(.init()))
        let coordinator = CaptureFreezeCoordinator(
            permissionChecker: PermissionChecker(hasAccess: false),
            capturer: capturer,
            cropper: CropperProbe(result: Data())
        )

        let result = await coordinator.startCapture()

        guard case .permissionRequired = result else {
            Issue.record("Expected permission recovery")
            return
        }
        #expect(await capturer.captureCount == 0)
    }

    @Test("one display failure preserves successful frozen displays")
    func partialDisplayFailure() async {
        let display = makeFrozenDisplay(id: 1, width: 20, height: 20)
        let failure = DisplayCaptureFailure(
            displayID: 2,
            reason: .captureFailed
        )
        let capturer = FrozenDisplayCapturerProbe(
            result: .success(
                FrozenDisplayBatch(
                    displays: [display],
                    failures: [failure]
                )
            )
        )
        let coordinator = CaptureFreezeCoordinator(
            permissionChecker: PermissionChecker(hasAccess: true),
            capturer: capturer,
            cropper: CropperProbe(result: Data())
        )

        let result = await coordinator.startCapture()

        guard case let .ready(session, displays, failures) = result else {
            Issue.record("Expected a usable partial capture")
            return
        }
        #expect(displays.map(\.geometry.displayID) == [1])
        #expect(failures == [failure])
        #expect(await session.availableDisplayIDs == [1])
    }

    @Test("all per-display failures exit without a selection session")
    func allDisplayFailures() async {
        let failures = [
            DisplayCaptureFailure(displayID: 1, reason: .captureFailed),
            DisplayCaptureFailure(displayID: 2, reason: .displayDisconnected),
        ]
        let coordinator = CaptureFreezeCoordinator(
            permissionChecker: PermissionChecker(hasAccess: true),
            capturer: FrozenDisplayCapturerProbe(
                result: .success(
                    FrozenDisplayBatch(displays: [], failures: failures)
                )
            ),
            cropper: CropperProbe(result: Data())
        )

        let result = await coordinator.startCapture()

        guard case let .allDisplaysFailed(actual) = result else {
            Issue.record("Expected all-displays-failed")
            return
        }
        #expect(actual == failures)
    }

    @Test("a permission denial reported during discovery uses permission recovery")
    func discoveryPermissionDenial() async {
        let coordinator = CaptureFreezeCoordinator(
            permissionChecker: PermissionChecker(hasAccess: true),
            capturer: FrozenDisplayCapturerProbe(
                result: .failure(CaptureDiscoveryError.permissionDenied)
            ),
            cropper: CropperProbe(result: Data())
        )

        let result = await coordinator.startCapture()

        guard case .permissionRequired = result else {
            Issue.record("Expected permission recovery")
            return
        }
    }
}

private struct PermissionChecker: ScreenCapturePermissionChecking {
    let hasAccess: Bool

    func hasScreenCaptureAccess() -> Bool {
        hasAccess
    }
}

private actor FrozenDisplayCapturerProbe: FrozenDisplayCapturing {
    let result: Result<FrozenDisplayBatch, CaptureDiscoveryError>
    private(set) var captureCount = 0

    init(result: Result<FrozenDisplayBatch, CaptureDiscoveryError>) {
        self.result = result
    }

    func captureFrozenDisplays() async throws(CaptureDiscoveryError) -> FrozenDisplayBatch {
        captureCount += 1
        return try result.get()
    }
}
