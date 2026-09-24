import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Live provider result validation")
struct LiveProviderResultValidationTests {
    // Empty source plus stop/DONE mirrors the observed 2026-09-24 DeepSeek event shape.
    // These offline fixtures validate detection, not current account/model capability.
    @Test("known text extraction rejects empty or whitespace output", arguments: ["", " \n\t"])
    func emptyTextFails(source: String) async throws {
        let reports = await run(source: source)
        #expect(reports.count == 2)
        #expect(reports.allSatisfy { $0.outcome == .failed })
    }

    @Test("known text matches across harmless whitespace and validates both operations")
    func correctTextPasses() async throws {
        let reports = await run(source: " \nVLMSnapper\t")
        #expect(reports.count == 2)
        #expect(reports.map(\.operation) == [.extract, .translate])
        #expect(reports.allSatisfy { $0.outcome == .passed })
    }

    @Test("observed bold extraction preserves known text but translation source remains plain")
    func markdownExtractionPasses() async throws {
        // Matches the real Flash diagnostic: 14 characters, strong_stars shape.
        let reports = await run(source: "**VLMSnapper**")
        #expect(reports.count == 2)
        #expect(reports[0].outcome == .passed)
        #expect(reports[1].outcome == .failed)
        #expect(reports[1].status == "source_mismatch")
    }

    @Test("inline styling does not change extraction text", arguments: ["*VLMSnapper*", "__VLMSnapper__", "`VLMSnapper`"])
    func inlineStylingPasses(source: String) async throws {
        let reports = await run(source: source)
        #expect(reports.count == 2)
        #expect(reports[0].outcome == .passed)
        #expect(reports[1].outcome == .failed)
    }

    @Test("formatting cannot hide wrong, extra, or literal punctuation text", arguments: [
        "**Wrong**", "**VLMSnapper** extra", "**VLMSnapper!**", "**vlmsnapper**",
        "\\*\\*VLMSnapper\\*\\*", "**VLMSnapper", "****",
    ])
    func styledMismatchFails(source: String) async throws {
        let reports = await run(source: source)
        #expect(reports.count == 2)
        #expect(reports.allSatisfy { $0.outcome == .failed })
        #expect(reports.allSatisfy { $0.status == "source_mismatch" })
    }

    @Test("correct source with blank translation still fails")
    func emptyTranslationFails() async throws {
        let gate = LiveProviderContractGate(streamer: ProviderAdapterExecutor(
            transport: ValidationHTTPTransport(source: "VLMSnapper", translation: " \n")
        ))
        let reports = await gate.run(
            configurations: [.deepSeek: .init(modelID: "deepseek-v4-pro", apiKey: "fixture-key")],
            originalPNG: Data([0x89]), expectedSource: "VLMSnapper", providers: [.deepSeek]
        )
        #expect(reports.count == 2)
        #expect(reports[0].outcome == .passed)
        #expect(reports[1].status == "empty_translation")
        #expect(reports[1].outcome == .failed)
    }

    @Test("reports do not contain response text or credentials")
    func reportsAreRedacted() async throws {
        let reports = await run(source: "private-response-text")
        let encoded = String(decoding: try JSONEncoder().encode(reports), as: UTF8.self)
        #expect(reports.count == 2)
        #expect(!encoded.contains("private-response-text"))
        #expect(!encoded.contains("fixture-key"))
        #expect(!encoded.contains("fixture-request"))
    }

    private func run(source: String) async -> [LiveProviderContractReport] {
        await LiveProviderContractGate(streamer: ProviderAdapterExecutor(
            transport: ValidationHTTPTransport(source: source)
        )).run(
            configurations: [.deepSeek: .init(modelID: "deepseek-v4-pro", apiKey: "fixture-key")],
            originalPNG: Data([0x89]), expectedSource: "VLMSnapper", providers: [.deepSeek]
        )
    }
    @Test("known text fixture rejects a completed but incorrect extraction")
    func incorrectTextFails() async throws {
        let gate = LiveProviderContractGate(streamer: ProviderAdapterExecutor(
            transport: ValidationHTTPTransport(source: "Unrelated text")
        ))
        let reports = await gate.run(
            configurations: [.deepSeek: .init(modelID: "deepseek-v4-pro", apiKey: "fixture-key")],
            originalPNG: Data([0x89, 0x50, 0x4e, 0x47]),
            expectedSource: "VLMSnapper"
        )
        let extraction = try #require(reports.first { $0.provider == .deepSeek && $0.operation == .extract })
        #expect(extraction.outcome == .failed)
        #expect(extraction.status == "source_mismatch")
    }
}

private struct ValidationHTTPTransport: ProviderHTTPStreaming {
    let source: String
    var translation = "视觉截图工具"

    func stream(for request: URLRequest) async throws -> ProviderHTTPStreamResponse {
        let isTranslation = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            .contains("translation prompt v2")
        // Literal field ordering is part of the streaming contract.
        let content: String
        if isTranslation {
            func quote(_ text: String) throws -> String {
                String(decoding: try JSONEncoder().encode(text), as: UTF8.self)
            }
            content = "{\"segments\":[{\"id\":\"s1\",\"block\":\"p1\",\"kind\":\"paragraph\",\"source\":\(try quote(source)),\"translation\":\(try quote(translation))}]}"
        } else {
            content = String(decoding: try JSONSerialization.data(withJSONObject: ["source": source]), as: UTF8.self)
        }
        let chunk: [String: Any] = [
            "id": "fixture-request", "choices": [[
                "index": 0, "delta": ["content": content], "finish_reason": "stop",
            ]],
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: chunk), as: UTF8.self)
        let data = Data("data: \(json)\n\ndata: [DONE]\n\n".utf8)
        return ProviderHTTPStreamResponse(statusCode: 200, headers: [:], body: AsyncThrowingStream {
            $0.yield(data)
            $0.finish()
        })
    }
}
