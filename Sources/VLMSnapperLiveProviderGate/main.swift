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
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            print(usage)
            return
        }
        guard let options = Options(arguments) else {
            FileHandle.standardError.write(
                Data((usage + "\n").utf8)
            )
            exit(EX_USAGE)
        }

        do {
            let outputURL = URL(fileURLWithPath: options.output)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            var configurations = LiveProviderContractEnvironment.configurations(
                from: ProcessInfo.processInfo.environment
            )
            if let provider = options.provider, let model = options.model {
                let apiKey: String
                if options.keychain {
                    do {
                        apiKey = try await AppleKeychainProviderCredentialStore()
                            .credential(for: provider)?.apiKey ?? ""
                    } catch {
                        FileHandle.standardError.write(Data("Protected credential read failed; no requests sent.\n".utf8))
                        exit(EXIT_FAILURE)
                    }
                } else {
                    // Explicit model selection must not depend on a separate model env var.
                    let keyName: String
                    switch provider {
                    case .openAI: keyName = "OPENAI_API_KEY"
                    case .gemini: keyName = "GEMINI_API_KEY"
                    case .deepSeek: keyName = "DEEPSEEK_API_KEY"
                    }
                    apiKey = ProcessInfo.processInfo.environment[keyName] ?? ""
                }
                configurations = [provider: .init(modelID: model, apiKey: apiKey)]
            }
            let reports = await LiveProviderContractGate().run(
                configurations: configurations,
                originalPNG: try makeFixturePNG(),
                expectedSource: "VLMSnapper",
                providers: options.provider.map { [$0] } ?? ProviderID.allCases
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(reports)
            try data.write(to: outputURL, options: .atomic)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(!reports.isEmpty && reports.allSatisfy { $0.outcome == .passed } ? EX_OK : EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(
                Data("Unable to create the live Provider contract report.\n".utf8)
            )
            exit(EXIT_FAILURE)
        }
    }

    private static let usage = """
        Usage: VLMSnapperLiveProviderGate --output <report.json> [--provider <openai|gemini|deepseek> --model <id>] [--keychain]
        Sends one extraction and one translation request per selected provider; no retries.
        Uses a non-private known-text PNG and validates the final recognized text.
        Default: all three providers configured by API-key/model environment variables.
        --keychain: requires explicit provider/model and a correctly signed test executable.
        No credentials, source text or raw responses are included in the report.
        """

    private struct Options {
        let output: String
        let provider: ProviderID?
        let model: String?
        let keychain: Bool

        init?(_ arguments: [String]) {
            var values: [String: String] = [:]
            var keychain = false
            var index = 0
            while index < arguments.count {
                let key = arguments[index]
                if key == "--keychain" {
                    guard !keychain else { return nil }
                    keychain = true
                    index += 1
                    continue
                }
                guard ["--output", "--provider", "--model"].contains(key),
                      values[key] == nil, index + 1 < arguments.count else { return nil }
                let value = arguments[index + 1]
                guard !value.hasPrefix("--"), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                values[key] = value
                index += 2
            }
            guard let output = values["--output"],
                  (values["--provider"] == nil) == (values["--model"] == nil) else { return nil }
            let provider = values["--provider"].flatMap(ProviderID.init(rawValue:))
            guard values["--provider"] == nil || provider != nil,
                  !keychain || provider != nil else { return nil }
            self.output = output
            self.provider = provider
            self.model = values["--model"]
            self.keychain = keychain
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
