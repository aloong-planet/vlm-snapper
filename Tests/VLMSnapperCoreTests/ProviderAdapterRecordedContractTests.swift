import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Recorded provider adapter contract")
struct ProviderAdapterRecordedContractTests {
    @Test("all providers produce the same ordered translation contract", arguments: fixtures)
    func allProvidersProduceOrderedTranslation(fixture: AdapterFixture) async throws {
        let transport = FixtureStreamingTransport(body: fixture.body)
        let executor = ProviderAdapterExecutor(transport: transport)
        var events: [ProviderStreamEvent] = []

        for try await event in executor.stream(
            provider: fixture.provider,
            modelID: fixture.modelID,
            apiKey: "secret",
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
            operation: .translate(targetLanguage: "es")
        ) {
            events.append(event)
        }

        #expect(events == [
            .sourceDelta("Hello"),
            .translationDelta("Hola"),
            .metadata(
                ProviderResponseMetadata(
                    requestID: fixture.requestID,
                    usage: fixture.usage
                )
            ),
            .completed,
        ])
        #expect(await transport.requestCount == 1)
    }

    static let fixtures: [AdapterFixture] = [
        AdapterFixture(
            provider: .openAI,
            modelID: "gpt-4.1",
            requestID: "resp_contract",
            usage: ProviderTokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15),
            payloads: [
                #"{"type":"response.output_text.delta","delta":"{\"source\":\"Hello\""}"#,
                #"{"type":"response.output_text.delta","delta":",\"translation\":\"Hola\"}"}"#,
                #"{"type":"response.completed","response":{"id":"resp_contract","status":"completed","usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}}"#,
            ]
        ),
        AdapterFixture(
            provider: .gemini,
            modelID: "gemini-2.5-flash",
            requestID: "gem_contract",
            usage: ProviderTokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15),
            payloads: [
                #"{"responseId":"gem_contract","candidates":[{"index":0,"content":{"parts":[{"text":"{\"source\":\"Hello\""}]}}]}"#,
                #"{"responseId":"gem_contract","candidates":[{"index":0,"content":{"parts":[{"text":",\"translation\":\"Hola\"}"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15}}"#,
            ]
        ),
        AdapterFixture(
            provider: .deepSeek,
            modelID: "deepseek-v4-flash-vision-exp",
            requestID: "chat_contract",
            usage: ProviderTokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15),
            payloads: [
                #"{"id":"chat_contract","choices":[{"index":0,"delta":{"content":"{\"source\":\"Hello\""},"finish_reason":null}]}"#,
                #"{"id":"chat_contract","choices":[{"index":0,"delta":{"content":",\"translation\":\"Hola\"}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#,
                "[DONE]",
            ]
        ),
    ]
}

struct AdapterFixture: Sendable, CustomTestStringConvertible {
    let provider: ProviderID
    let modelID: String
    let requestID: String
    let usage: ProviderTokenUsage
    let body: Data

    init(
        provider: ProviderID,
        modelID: String,
        requestID: String,
        usage: ProviderTokenUsage,
        payloads: [String]
    ) {
        self.provider = provider
        self.modelID = modelID
        self.requestID = requestID
        self.usage = usage
        body = Data(payloads.map { "data: \($0)\n\n" }.joined().utf8)
    }

    var testDescription: String { provider.rawValue }
}

private actor FixtureStreamingTransport: ProviderHTTPStreaming {
    private(set) var requestCount = 0
    private let body: Data

    init(body: Data) {
        self.body = body
    }

    func stream(for request: URLRequest) async throws -> ProviderHTTPStreamResponse {
        requestCount += 1
        return ProviderHTTPStreamResponse(
            statusCode: 200,
            headers: [:],
            body: AsyncThrowingStream { continuation in
                continuation.yield(body)
                continuation.finish()
            }
        )
    }
}
