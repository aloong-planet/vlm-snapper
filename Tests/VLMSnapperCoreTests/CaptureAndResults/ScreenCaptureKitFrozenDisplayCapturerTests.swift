import CoreGraphics
import Testing
@testable import VLMSnapperCore

@Suite("ScreenCaptureKit frozen display capture")
struct ScreenCaptureKitFrozenDisplayCapturerTests {
    // A one-times display keeps its size, a Retina one doubles, fractions round to the nearest pixel,
    // and a size that rounds to zero or leaves the Int range is rejected.
    @Test("filter geometry converts to physical pixel dimensions", arguments: [
        (1920.0, 1080.0, 1.0, CaptureRasterSize(width: 1920, height: 1080)),
        (1512, 982, 2, CaptureRasterSize(width: 3024, height: 1964)),
        (100.25, 50.25, 2, CaptureRasterSize(width: 201, height: 101)),
        (0.2, 100, 1, nil),
        (Double(Int.max), 100, 1, nil),
    ] as [(Double, Double, Float, CaptureRasterSize?)])
    func rasterSizeCountsPhysicalPixels(
        width: Double,
        height: Double,
        scale: Float,
        expected: CaptureRasterSize?
    ) {
        let size = captureRasterSize(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            pointPixelScale: scale
        )

        #expect(size == expected)
    }
}
