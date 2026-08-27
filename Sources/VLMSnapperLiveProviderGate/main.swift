import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VLMSnapperCore

@main
enum VLMSnapperLiveProviderGateCommand {
    static func main() async {
        guard CommandLine.arguments.count == 3,
              CommandLine.arguments[1] == "--output" else {
            FileHandle.standardError.write(
                Data("Usage: VLMSnapperLiveProviderGate --output <report.json>\n".utf8)
            )
            exit(EX_USAGE)
        }

        do {
            let reports = await LiveProviderContractGate().run(
                configurations: LiveProviderContractEnvironment.configurations(
                    from: ProcessInfo.processInfo.environment
                ),
                originalPNG: try makeFixturePNG()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(reports)
            let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outputURL, options: .atomic)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(reports.allSatisfy { $0.outcome == .passed } ? EX_OK : EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(
                Data("Unable to create the live Provider contract report.\n".utf8)
            )
            exit(EXIT_FAILURE)
        }
    }

    private static func makeFixturePNG() throws -> Data {
        let width = 240
        let height = 72
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FixtureError.unavailable
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica-Bold" as CFString,
                30,
                nil
            ),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                gray: 0,
                alpha: 1
            ),
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: "VLMSnapper", attributes: attributes)
        )
        let bounds = CTLineGetBoundsWithOptions(line, [])
        context.textPosition = CGPoint(
            x: (CGFloat(width) - bounds.width) / 2,
            y: 23
        )
        CTLineDraw(line, context)
        guard let image = context.makeImage() else {
            throw FixtureError.unavailable
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw FixtureError.unavailable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.unavailable
        }
        return output as Data
    }
}

private enum FixtureError: Error {
    case unavailable
}
