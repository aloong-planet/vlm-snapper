import CoreGraphics
import Foundation
@testable import VLMSnapperCore

/// A frozen display of the given pixel size at scale 1, with an empty sRGB frame.
func makeFrozenDisplay(
    id: UInt32,
    width: Int,
    height: Int
) -> FrozenCaptureDisplay {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return FrozenCaptureDisplay(
        geometry: CaptureDisplayGeometry(
            displayID: id,
            logicalX: 0,
            logicalY: 0,
            logicalWidth: Double(width),
            logicalHeight: Double(height),
            pixelWidth: width,
            pixelHeight: height,
            rotationDegrees: 0
        ),
        frame: FrozenDisplayFrame(image: context.makeImage()!)
    )
}

/// Returns a fixed PNG and records the display and rectangle of the last crop.
actor CropperProbe: CaptureImageCropping {
    let result: Data
    private(set) var lastDisplayID: UInt32?
    private(set) var lastRect: PixelRect?

    init(result: Data) {
        self.result = result
    }

    func cropPNG(
        frame: FrozenDisplayFrame,
        displayID: UInt32,
        pixelRect: PixelRect
    ) async throws -> Data {
        lastDisplayID = displayID
        lastRect = pixelRect
        return result
    }
}
