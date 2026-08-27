import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Live provider contract gate")
struct LiveProviderContractGateTests {
    @Test("missing provider configuration is blocked without a network request")
    func missingConfigurationIsBlockedWithoutRequest() async {
        let streamer = LiveContractFixtureStreamer(events: [])
        let gate = LiveProviderContractGate(
            streamer: streamer,
            nowMilliseconds: { 1_000 }
        )

        let reports = await gate.run(
            configurations: [:],
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47])
        )

        #expect(reports == ProviderID.allCases.map {
            LiveProviderContractReport(
                provider: $0,
                modelID: nil,
                stage: .configuration,
                outcome: .blocked,
                durationMilliseconds: 0,
                status: "missing_configuration",
                requestID: nil,
                usage: nil
            )
        })
        #expect(await streamer.requestCount == 0)
    }

    @Test("a configured provider passes only after a complete translated stream")
    func configuredProviderPassesCompleteTranslation() async {
        let usage = ProviderTokenUsage(inputTokens: 12, outputTokens: 7, totalTokens: 19)
        let streamer = LiveContractFixtureStreamer(events: [
            .sourceDelta("VLMSnapper"),
            .translationDelta("视觉截图工具"),
            .metadata(ProviderResponseMetadata(requestID: "request-secret", usage: usage)),
            .completed,
        ])
        let gate = LiveProviderContractGate(
            streamer: streamer,
            nowMilliseconds: { 2_000 }
        )
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

        let reports = await gate.run(
            configurations: [
                .gemini: LiveProviderContractConfiguration(
                    modelID: "gemini-2.5-flash",
                    apiKey: "never-report-this-key"
                ),
            ],
            originalPNG: png
        )

        #expect(reports[1] == LiveProviderContractReport(
            provider: .gemini,
            modelID: "gemini-2.5-flash",
            stage: .validation,
            outcome: .passed,
            durationMilliseconds: 0,
            status: "passed",
            requestID: "sha256:455590bece67",
            usage: LiveProviderContractUsage(
                inputTokens: 12,
                outputTokens: 7,
                totalTokens: 19
            )
        ))
        #expect(await streamer.requestCount == 1)
        #expect(await streamer.lastRequest == LiveContractRequest(
            provider: .gemini,
            modelID: "gemini-2.5-flash",
            apiKey: "never-report-this-key",
            originalPNG: png,
            operation: .translate(targetLanguage: "Simplified Chinese")
        ))
    }

    @Test("blank model or credential is blocked without a network request")
    func blankConfigurationIsBlockedWithoutRequest() async {
        let streamer = LiveContractFixtureStreamer(events: [])
        let gate = LiveProviderContractGate(streamer: streamer)

        let reports = await gate.run(
            configurations: [
                .openAI: LiveProviderContractConfiguration(
                    modelID: "   ",
                    apiKey: "secret"
                ),
                .gemini: LiveProviderContractConfiguration(
                    modelID: "gemini-2.5-flash",
                    apiKey: "\n\t"
                ),
            ],
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47])
        )

        #expect(reports[0].outcome == .blocked)
        #expect(reports[0].status == "missing_configuration")
        #expect(reports[1].outcome == .blocked)
        #expect(reports[1].status == "missing_configuration")
        #expect(await streamer.requestCount == 0)
    }

    @Test("environment configuration requires a key and model for each provider")
    func environmentConfigurationRequiresKeyAndModel() {
        let configurations = LiveProviderContractEnvironment.configurations(from: [
            "OPENAI_API_KEY": "openai-key",
            "VLMSNAPPER_OPENAI_MODEL": "gpt-5-mini",
            "GEMINI_API_KEY": "gemini-key",
            "VLMSNAPPER_GEMINI_MODEL": "",
            "DEEPSEEK_API_KEY": "deepseek-key",
            "VLMSNAPPER_DEEPSEEK_MODEL": "deepseek-v4-flash-vision-exp",
        ])

        #expect(configurations == [
            .openAI: LiveProviderContractConfiguration(
                modelID: "gpt-5-mini",
                apiKey: "openai-key"
            ),
            .deepSeek: LiveProviderContractConfiguration(
                modelID: "deepseek-v4-flash-vision-exp",
                apiKey: "deepseek-key"
            ),
        ])
    }

    @Test("provider failures are normalized without leaking request content")
    func providerFailureIsNormalizedAndRedacted() async throws {
        let gate = LiveProviderContractGate(
            streamer: LiveContractFailingStreamer(
                error: ProviderAdapterError.rateLimited(retryAfterSeconds: 45)
            ),
            nowMilliseconds: { 4_000 }
        )

        let reports = await gate.run(
            configurations: [
                .openAI: LiveProviderContractConfiguration(
                    modelID: "gpt-5-mini",
                    apiKey: "never-report-this-key"
                ),
            ],
            originalPNG: Data("never-report-image-or-result".utf8)
        )

        #expect(reports[0].stage == .request)
        #expect(reports[0].outcome == .failed)
        #expect(reports[0].status == "rate_limited")
        let encoded = String(decoding: try JSONEncoder().encode(reports), as: UTF8.self)
        #expect(!encoded.contains("never-report-this-key"))
        #expect(!encoded.contains("never-report-image-or-result"))
        #expect(!encoded.contains("45"))
    }

    @Test("a stream without a completed output fails validation")
    func incompleteStreamFailsValidation() async {
        let gate = LiveProviderContractGate(
            streamer: LiveContractFixtureStreamer(events: [
                .sourceDelta("VLMSnapper"),
            ])
        )

        let reports = await gate.run(
            configurations: [
                .deepSeek: LiveProviderContractConfiguration(
                    modelID: "deepseek-v4-flash-vision-exp",
                    apiKey: "secret"
                ),
            ],
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47])
        )

        #expect(reports[2].stage == .validation)
        #expect(reports[2].outcome == .failed)
        #expect(reports[2].status == "incomplete_response")
    }
}

private struct LiveContractRequest: Equatable, Sendable {
    let provider: ProviderID
    let modelID: String
    let apiKey: String
    let originalPNG: Data
    let operation: ProviderOperation
}

private actor LiveContractFixtureStreamer: LiveProviderContractStreaming {
    private(set) var requestCount = 0
    private(set) var lastRequest: LiveContractRequest?
    private let events: [ProviderStreamEvent]

    init(events: [ProviderStreamEvent]) {
        self.events = events
    }

    nonisolated func stream(
        provider: ProviderID,
        modelID: String,
        apiKey: String,
        originalPNG: Data,
        operation: ProviderOperation
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await recordRequest(LiveContractRequest(
                    provider: provider,
                    modelID: modelID,
                    apiKey: apiKey,
                    originalPNG: originalPNG,
                    operation: operation
                ))
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    private func recordRequest(_ request: LiveContractRequest) {
        requestCount += 1
        lastRequest = request
    }
}

private struct LiveContractFailingStreamer: LiveProviderContractStreaming {
    let error: ProviderAdapterError

    func stream(
        provider: ProviderID,
        modelID: String,
        apiKey: String,
        originalPNG: Data,
        operation: ProviderOperation
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}
