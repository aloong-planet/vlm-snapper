import CoreGraphics
import Testing
@testable import VLMSnapperCore

@Suite("ScreenCaptureKit frozen display capture")
struct ScreenCaptureKitFrozenDisplayCapturerTests {
    @Test("A one-times display preserves its logical dimensions")
    func preservesOneTimesDimensions() {
        let size = captureRasterSize(
            contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            pointPixelScale: 1
        )

        #expect(size == CaptureRasterSize(width: 1920, height: 1080))
    }

    @Test("Retina filter geometry converts to physical pixel dimensions")
    func convertsRetinaGeometryToPhysicalPixels() {
        let size = captureRasterSize(
            contentRect: CGRect(x: 0, y: 0, width: 1512, height: 982),
            pointPixelScale: 2
        )

        #expect(size == CaptureRasterSize(width: 3024, height: 1964))
    }

    @Test("Fractional physical dimensions round to the nearest pixel")
    func roundsFractionalPhysicalDimensions() {
        let size = captureRasterSize(
            contentRect: CGRect(x: 0, y: 0, width: 100.25, height: 50.25),
            pointPixelScale: 2
        )

        #expect(size == CaptureRasterSize(width: 201, height: 101))
    }

    @Test("A raster dimension that rounds to zero is rejected")
    func rejectsRoundedZeroDimension() {
        let size = captureRasterSize(
            contentRect: CGRect(x: 0, y: 0, width: 0.2, height: 100),
            pointPixelScale: 1
        )

        #expect(size == nil)
    }

    @Test("A raster dimension outside the Int range is rejected")
    func rejectsIntegerOverflow() {
        let size = captureRasterSize(
            contentRect: CGRect(
                x: 0,
                y: 0,
                width: Double(Int.max),
                height: 100
            ),
            pointPixelScale: 1
        )

        #expect(size == nil)
    }
}
