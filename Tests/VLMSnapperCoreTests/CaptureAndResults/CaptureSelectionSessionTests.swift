import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Capture selection session")
struct CaptureSelectionSessionTests {
    @Test("selection is cropped from the trigger-time frozen frame and keeps the frames for adjustment")
    func selectionUsesFrozenFrameAndKeepsDisplays() async throws {
        let first = makeFrozenDisplay(id: 1, width: 100, height: 80)
        let second = makeFrozenDisplay(id: 2, width: 200, height: 120)
        let cropper = CropperProbe(result: Data([0x89, 0x50, 0x4E, 0x47]))
        let session = CaptureSelectionSession(
            displays: [first, second],
            cropper: cropper
        )

        try await session.beginSelection(
            on: 2,
            at: CapturePoint(x: 10.2, y: 8.8)
        )
        try await session.updateSelection(to: CapturePoint(x: 24.1, y: 30.2))
        let result = try await session.finishSelection(
            currentGeometry: second.geometry
        )

        #expect(result.displayID == 2)
        #expect(result.pixelRect == PixelRect(x: 10, y: 8, width: 15, height: 23))
        #expect(result.originalPNG == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(await cropper.lastDisplayID == 2)
        #expect(await cropper.lastRect == result.pixelRect)
        #expect(await session.state == .selected)
        #expect(await session.availableDisplayIDs == [1, 2])
    }

    // v1-core::REQ-007: a confirmed selection can be replaced or adjusted until the session ends.
    @Test("a confirmed selection can be adjusted and is cropped again from the same frame")
    func confirmedSelectionCanBeAdjusted() async throws {
        let display = makeFrozenDisplay(id: 1, width: 100, height: 80)
        let cropper = CropperProbe(result: Data([0x89, 0x50, 0x4E, 0x47]))
        let session = CaptureSelectionSession(displays: [display], cropper: cropper)
        try await session.beginSelection(on: 1, at: CapturePoint(x: 10, y: 10))
        try await session.updateSelection(to: CapturePoint(x: 30, y: 20))
        let first = try await session.finishSelection(currentGeometry: display.geometry)

        try await session.beginSelection(on: 1, at: CapturePoint(x: 5, y: 6))
        try await session.updateSelection(to: CapturePoint(x: 45, y: 36))
        let adjusted = try await session.finishSelection(currentGeometry: display.geometry)

        #expect(first.pixelRect == PixelRect(x: 10, y: 10, width: 20, height: 10))
        #expect(adjusted.pixelRect == PixelRect(x: 5, y: 6, width: 40, height: 30))
        #expect(await cropper.lastRect == adjusted.pixelRect)
        #expect(await session.state == .selected)
    }

    @Test("an adjustment under two pixels is rejected and the selection can still be adjusted")
    func tinyAdjustmentKeepsSelectionAdjustable() async throws {
        let display = makeFrozenDisplay(id: 1, width: 100, height: 80)
        let session = CaptureSelectionSession(
            displays: [display],
            cropper: CropperProbe(result: Data([0x89]))
        )
        try await session.beginSelection(on: 1, at: CapturePoint(x: 10, y: 10))
        try await session.updateSelection(to: CapturePoint(x: 30, y: 20))
        _ = try await session.finishSelection(currentGeometry: display.geometry)

        try await session.beginSelection(on: 1, at: CapturePoint(x: 10, y: 10))
        try await session.updateSelection(to: CapturePoint(x: 11, y: 11))
        await #expect(throws: CaptureSelectionError.selectionTooSmall) {
            _ = try await session.finishSelection(currentGeometry: display.geometry)
        }
        #expect(await session.state == .selected)
        try await session.beginSelection(on: 1, at: CapturePoint(x: 0, y: 0))
        try await session.updateSelection(to: CapturePoint(x: 4, y: 4))
        let valid = try await session.finishSelection(currentGeometry: display.geometry)
        #expect(valid.pixelRect == PixelRect(x: 0, y: 0, width: 4, height: 4))
    }

    @Test("losing every frozen display ends the session, with or without a selection", arguments: [false, true])
    func losingEveryDisplayEndsTheSession(afterSelection: Bool) async throws {
        let display = makeFrozenDisplay(id: 1, width: 100, height: 80)
        let session = CaptureSelectionSession(
            displays: [display],
            cropper: CropperProbe(result: Data([0x89]))
        )
        if afterSelection {
            try await session.beginSelection(on: 1, at: CapturePoint(x: 10, y: 10))
            try await session.updateSelection(to: CapturePoint(x: 30, y: 20))
            _ = try await session.finishSelection(currentGeometry: display.geometry)
        }

        let invalidated = await session.applyCurrentDisplayGeometries([])
        #expect(invalidated == [1])
        #expect(await session.state == .noDisplaysAvailable)
        await #expect(throws: CaptureSelectionError.inactiveSession) {
            try await session.beginSelection(on: 1, at: CapturePoint(x: 1, y: 1))
        }
    }

    @Test("cancelling after a selection ends the session")
    func cancelAfterSelectionEndsSession() async throws {
        let display = makeFrozenDisplay(id: 1, width: 100, height: 80)
        let session = CaptureSelectionSession(
            displays: [display],
            cropper: CropperProbe(result: Data([0x89]))
        )
        try await session.beginSelection(on: 1, at: CapturePoint(x: 10, y: 10))
        try await session.updateSelection(to: CapturePoint(x: 30, y: 20))
        _ = try await session.finishSelection(currentGeometry: display.geometry)

        await session.cancel()

        #expect(await session.state == .cancelled)
        #expect(await session.availableDisplayIDs.isEmpty)
        await #expect(throws: CaptureSelectionError.inactiveSession) {
            try await session.beginSelection(on: 1, at: CapturePoint(x: 1, y: 1))
        }
    }

    @Test("a selection smaller than two physical pixels is rejected")
    func rejectsSelectionSmallerThanTwoPixels() async throws {
        let display = makeFrozenDisplay(id: 3, width: 100, height: 80)
        let session = CaptureSelectionSession(
            displays: [display],
            cropper: CropperProbe(result: Data())
        )

        try await session.beginSelection(
            on: 3,
            at: CapturePoint(x: 10.1, y: 10.1)
        )
        try await session.updateSelection(to: CapturePoint(x: 10.9, y: 11.1))

        await #expect(throws: CaptureSelectionError.selectionTooSmall) {
            try await session.finishSelection(currentGeometry: display.geometry)
        }
        #expect(await session.state == .selecting)
        #expect(await session.availableDisplayIDs == [3])
    }

    @Test("geometry changes invalidate only the affected display and cancel its drag")
    func invalidatesOnlyChangedDisplay() async throws {
        let first = makeFrozenDisplay(id: 10, width: 100, height: 80)
        let second = makeFrozenDisplay(id: 11, width: 200, height: 120)
        let session = CaptureSelectionSession(
            displays: [first, second],
            cropper: CropperProbe(result: Data())
        )
        try await session.beginSelection(
            on: 10,
            at: CapturePoint(x: 2, y: 2)
        )
        let changedFirst = CaptureDisplayGeometry(
            displayID: 10,
            logicalX: 0,
            logicalY: 0,
            logicalWidth: 100,
            logicalHeight: 80,
            pixelWidth: 120,
            pixelHeight: 80,
            rotationDegrees: 0
        )

        let invalidated = await session.applyCurrentDisplayGeometries([
            changedFirst,
            second.geometry,
            makeFrozenDisplay(id: 12, width: 300, height: 200).geometry,
        ])

        #expect(invalidated == [10])
        #expect(await session.availableDisplayIDs == [11])
        #expect(await session.activeSelection == nil)
        #expect(await session.state == .selecting)
    }

    @Test("cancelling while the crop is suspended cannot resurrect the session")
    func cancellationDuringCropDoesNotComplete() async throws {
        let display = makeFrozenDisplay(id: 30, width: 100, height: 80)
        let cropper = SuspendedCropper()
        let session = CaptureSelectionSession(
            displays: [display],
            cropper: cropper
        )
        try await session.beginSelection(
            on: 30,
            at: CapturePoint(x: 2, y: 2)
        )
        try await session.updateSelection(to: CapturePoint(x: 20, y: 20))
        let finishing = Task {
            try await session.finishSelection(
                currentGeometry: display.geometry
            )
        }
        await cropper.waitUntilStarted()

        await session.cancel()
        await cropper.succeed()

        await #expect(throws: CaptureSelectionError.inactiveSession) {
            try await finishing.value
        }
        #expect(await session.state == .cancelled)
        #expect(await session.availableDisplayIDs.isEmpty)
    }

    @Test("a selected display changing during crop preserves other displays")
    func selectedDisplayChangeDuringCrop() async throws {
        let selected = makeFrozenDisplay(id: 40, width: 100, height: 80)
        let other = makeFrozenDisplay(id: 41, width: 120, height: 90)
        let cropper = SuspendedCropper()
        let session = CaptureSelectionSession(
            displays: [selected, other],
            cropper: cropper
        )
        try await session.beginSelection(
            on: 40,
            at: CapturePoint(x: 2, y: 2)
        )
        try await session.updateSelection(to: CapturePoint(x: 20, y: 20))
        let finishing = Task {
            try await session.finishSelection(
                currentGeometry: selected.geometry
            )
        }
        await cropper.waitUntilStarted()

        let invalidated = await session.applyCurrentDisplayGeometries([
            other.geometry,
        ])
        await cropper.succeed()

        #expect(invalidated == [40])
        await #expect(throws: CaptureSelectionError.displayGeometryChanged) {
            try await finishing.value
        }
        #expect(await session.state == .selecting)
        #expect(await session.availableDisplayIDs == [41])
    }

    @Test("cancellation wins when a suspended crop later fails")
    func cancellationWinsOverCropFailure() async throws {
        let display = makeFrozenDisplay(id: 50, width: 100, height: 80)
        let cropper = SuspendedCropper()
        let session = CaptureSelectionSession(
            displays: [display],
            cropper: cropper
        )
        try await session.beginSelection(
            on: 50,
            at: CapturePoint(x: 2, y: 2)
        )
        try await session.updateSelection(to: CapturePoint(x: 20, y: 20))
        let finishing = Task {
            try await session.finishSelection(
                currentGeometry: display.geometry
            )
        }
        await cropper.waitUntilStarted()

        await session.cancel()
        await cropper.fail()

        await #expect(throws: CaptureSelectionError.inactiveSession) {
            try await finishing.value
        }
        #expect(await session.state == .cancelled)
    }
}

private actor SuspendedCropper: CaptureImageCropping {
    private var resultContinuation: CheckedContinuation<Data, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func cropPNG(
        frame: FrozenDisplayFrame,
        displayID: UInt32,
        pixelRect: PixelRect
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilStarted() async {
        guard resultContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func succeed() {
        resultContinuation?.resume(returning: Data([0x89, 0x50, 0x4E, 0x47]))
        resultContinuation = nil
    }

    func fail() {
        resultContinuation?.resume(throwing: SuspendedCropError.failed)
        resultContinuation = nil
    }
}

private enum SuspendedCropError: Error {
    case failed
}
