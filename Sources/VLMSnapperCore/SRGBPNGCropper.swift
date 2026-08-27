import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CaptureImageCropError: Error, Equatable {
    case invalidPixelRect
    case cropFailed
    case renderFailed
    case pngEncodingFailed
}

public struct SRGBPNGCropper: CaptureImageCropping {
    public init() {}

    public func cropPNG(
        frame: FrozenDisplayFrame,
        displayID: UInt32,
        pixelRect: PixelRect
    ) async throws -> Data {
        guard pixelRect.x >= 0,
              pixelRect.y >= 0,
              pixelRect.width > 0,
              pixelRect.height > 0,
              pixelRect.width <= frame.image.width,
              pixelRect.height <= frame.image.height,
              pixelRect.x <= frame.image.width - pixelRect.width,
              pixelRect.y <= frame.image.height - pixelRect.height
        else {
            throw CaptureImageCropError.invalidPixelRect
        }
        let cropBounds = CGRect(
            x: pixelRect.x,
            y: pixelRect.y,
            width: pixelRect.width,
            height: pixelRect.height
        )
        guard let cropped = frame.image.cropping(to: cropBounds) else {
            throw CaptureImageCropError.cropFailed
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelRect.width,
                  height: pixelRect.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                      | CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw CaptureImageCropError.renderFailed
        }
        context.draw(
            cropped,
            in: CGRect(
                x: 0,
                y: 0,
                width: pixelRect.width,
                height: pixelRect.height
            )
        )
        guard let rendered = context.makeImage() else {
            throw CaptureImageCropError.renderFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureImageCropError.pngEncodingFailed
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureImageCropError.pngEncodingFailed
        }
        return output as Data
    }
}
