public enum CaptureCoordinateMapper {
    public static func pixelPoint(
        fromLocalAppKitPoint point: CapturePoint,
        geometry: CaptureDisplayGeometry
    ) -> CapturePoint {
        guard geometry.logicalWidth > 0, geometry.logicalHeight > 0 else {
            return CapturePoint(x: 0, y: 0)
        }
        let logicalX = min(max(point.x, 0), geometry.logicalWidth)
        let logicalY = min(max(point.y, 0), geometry.logicalHeight)
        return CapturePoint(
            x: logicalX / geometry.logicalWidth * Double(geometry.pixelWidth),
            y: (geometry.logicalHeight - logicalY)
                / geometry.logicalHeight
                * Double(geometry.pixelHeight)
        )
    }
}
