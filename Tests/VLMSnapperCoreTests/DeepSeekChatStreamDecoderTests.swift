import Testing
@testable import VLMSnapperCore

@Suite("DeepSeek Chat stream decoder")
struct DeepSeekChatStreamDecoderTests {
    @Test("a recorded stop and DONE stream produces ordered translation events")
    func stopAndDoneProduceOrderedTranslation() throws {
        var decoder = DeepSeekChatStreamDecoder(
            operation: .translate(targetLanguage: "es")
        )
        let payloads = [
            #"{"id":"chat_123","choices":[{"index":0,"delta":{"content":"{\"source\":\"Hello\""},"finish_reason":null}]}"#,
            #"{"id":"chat_123","choices":[{"index":0,"delta":{"content":",\"translation\":\"Hola\"}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":13,"completion_tokens":6,"total_tokens":19}}"#,
            "[DONE]",
        ]
        var events: [ProviderStreamEvent] = []

        for payload in payloads {
            events.append(contentsOf: try decoder.consume(payload))
        }
        try decoder.finish()

        #expect(
            events == [
                .sourceDelta("Hello"),
                .translationDelta("Hola"),
                .metadata(
                    ProviderResponseMetadata(
                        requestID: "chat_123",
                        usage: ProviderTokenUsage(
                            inputTokens: 13,
                            outputTokens: 6,
                            totalTokens: 19
                        )
                    )
                ),
                .completed,
            ]
        )
    }

    @Test("clean EOF without DONE is incomplete")
    func missingDoneIsIncomplete() throws {
        var decoder = DeepSeekChatStreamDecoder(operation: .extractText)
        _ = try decoder.consume(
            #"{"id":"chat_456","choices":[{"index":0,"delta":{"content":"{\"source\":\"Hello\"}"},"finish_reason":"stop"}]}"#
        )

        #expect(throws: ProviderAdapterError.incompleteResponse) {
            try decoder.finish()
        }
    }
}
