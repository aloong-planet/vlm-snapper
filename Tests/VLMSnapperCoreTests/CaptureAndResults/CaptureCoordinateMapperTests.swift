import Testing
@testable import VLMSnapperCore

@Suite("Capture coordinate mapper")
struct CaptureCoordinateMapperTests {
    @Test("AppKit points map to top-left physical pixels on a Retina display")
    func mapsRetinaPointAndFlipsVerticalAxis() {
        let geometry = CaptureDisplayGeometry(
            displayID: 7,
            logicalX: 0,
            logicalY: 0,
            logicalWidth: 1440,
            logicalHeight: 900,
            pixelWidth: 2880,
            pixelHeight: 1800,
            rotationDegrees: 0
        )

        let point = CaptureCoordinateMapper.pixelPoint(
            fromLocalAppKitPoint: CapturePoint(x: 100, y: 250),
            geometry: geometry
        )

        #expect(point == CapturePoint(x: 200, y: 1300))
    }

    @Test("points outside the overlay clamp to the frozen image bounds")
    func clampsOutsidePoints() {
        let geometry = CaptureDisplayGeometry(
            displayID: 8,
            logicalX: 0,
            logicalY: 0,
            logicalWidth: 100,
            logicalHeight: 80,
            pixelWidth: 200,
            pixelHeight: 160,
            rotationDegrees: 0
        )

        #expect(
            CaptureCoordinateMapper.pixelPoint(
                fromLocalAppKitPoint: CapturePoint(x: -5, y: 100),
                geometry: geometry
            ) == CapturePoint(x: 0, y: 0)
        )
        #expect(
            CaptureCoordinateMapper.pixelPoint(
                fromLocalAppKitPoint: CapturePoint(x: 110, y: -10),
                geometry: geometry
            ) == CapturePoint(x: 200, y: 160)
        )
    }
}
