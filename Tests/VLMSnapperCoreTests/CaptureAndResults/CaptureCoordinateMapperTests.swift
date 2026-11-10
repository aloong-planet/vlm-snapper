import Testing
@testable import VLMSnapperCore

@Suite("Capture coordinate mapper")
struct CaptureCoordinateMapperTests {
    private static let retina = CaptureDisplayGeometry(
        displayID: 7,
        logicalX: 0,
        logicalY: 0,
        logicalWidth: 1440,
        logicalHeight: 900,
        pixelWidth: 2880,
        pixelHeight: 1800,
        rotationDegrees: 0
    )
    private static let small = CaptureDisplayGeometry(
        displayID: 8,
        logicalX: 0,
        logicalY: 0,
        logicalWidth: 100,
        logicalHeight: 80,
        pixelWidth: 200,
        pixelHeight: 160,
        rotationDegrees: 0
    )

    // The first case maps a Retina point and flips the vertical axis; the other two lie outside the
    // overlay and clamp to the frozen image bounds.
    @Test("AppKit points map to top-left physical pixels and clamp to the frozen image", arguments: [
        (retina, CapturePoint(x: 100, y: 250), CapturePoint(x: 200, y: 1300)),
        (small, CapturePoint(x: -5, y: 100), CapturePoint(x: 0, y: 0)),
        (small, CapturePoint(x: 110, y: -10), CapturePoint(x: 200, y: 160)),
    ])
    func mapsPointsToTopLeftPixelsAndClamps(
        geometry: CaptureDisplayGeometry,
        point: CapturePoint,
        expected: CapturePoint
    ) {
        #expect(
            CaptureCoordinateMapper.pixelPoint(fromLocalAppKitPoint: point, geometry: geometry) == expected
        )
    }
}
