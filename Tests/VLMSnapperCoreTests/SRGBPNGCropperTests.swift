import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import VLMSnapperCore

@Suite("sRGB PNG cropper")
struct SRGBPNGCropperTests {
    @Test("crop output is an exact-size 8-bit sRGB PNG")
    func exactSizeEightBitSRGBPNG() async throws {
        let image = makeGradientImage(width: 8, height: 6)
        let cropper = SRGBPNGCropper()

        let png = try await cropper.cropPNG(
            frame: FrozenDisplayFrame(image: image),
            displayID: 7,
            pixelRect: PixelRect(x: 2, y: 1, width: 4, height: 3)
        )

        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let source = CGImageSourceCreateWithData(png as CFData, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(decoded.width == 4)
        #expect(decoded.height == 3)
        #expect(decoded.bitsPerComponent == 8)
        #expect(decoded.colorSpace?.name == CGColorSpace.sRGB)
    }

    @Test("an out-of-bounds crop is rejected")
    func rejectsOutOfBoundsCrop() async {
        let cropper = SRGBPNGCropper()
        let image = makeGradientImage(width: 8, height: 6)

        await #expect(throws: CaptureImageCropError.invalidPixelRect) {
            try await cropper.cropPNG(
                frame: FrozenDisplayFrame(image: image),
                displayID: 7,
                pixelRect: PixelRect(x: 7, y: 5, width: 2, height: 2)
            )
        }
    }

    @Test("pixel coordinates crop the matching source rows without resizing")
    func preservesSelectedPixelContent() async throws {
        let cropper = SRGBPNGCropper()
        let image = makeTwoRowImage()

        let png = try await cropper.cropPNG(
            frame: FrozenDisplayFrame(image: image),
            displayID: 8,
            pixelRect: PixelRect(x: 0, y: 0, width: 2, height: 1)
        )

        let source = CGImageSourceCreateWithData(png as CFData, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(decoded.width == 2)
        #expect(decoded.height == 1)
        #expect(readRGBA(decoded) == [
            255, 0, 0, 255,
            255, 0, 0, 255,
        ])
    }

    @Test("extreme coordinates are rejected instead of overflowing")
    func rejectsOverflowingCoordinates() async {
        let cropper = SRGBPNGCropper()
        let image = makeGradientImage(width: 8, height: 6)

        await #expect(throws: CaptureImageCropError.invalidPixelRect) {
            try await cropper.cropPNG(
                frame: FrozenDisplayFrame(image: image),
                displayID: 9,
                pixelRect: PixelRect(
                    x: Int.max,
                    y: 0,
                    width: 2,
                    height: 2
                )
            )
        }
    }
}

private func makeGradientImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.displayP3)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for y in 0..<height {
        for x in 0..<width {
            context.setFillColor(
                red: CGFloat(x) / CGFloat(width),
                green: CGFloat(y) / CGFloat(height),
                blue: 0.5,
                alpha: 1
            )
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return context.makeImage()!
}

private func makeTwoRowImage() -> CGImage {
    let rgba = Data([
        255, 0, 0, 255,
        255, 0, 0, 255,
        0, 0, 255, 255,
        0, 0, 255, 255,
    ])
    return CGImage(
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 8,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        ),
        provider: CGDataProvider(data: rgba as CFData)!,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private func readRGBA(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
    }
    return bytes
}
