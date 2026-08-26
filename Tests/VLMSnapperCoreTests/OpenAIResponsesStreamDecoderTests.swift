import Testing
@testable import VLMSnapperCore

@Suite("OpenAI Responses stream decoder")
struct OpenAIResponsesStreamDecoderTests {
    @Test("a recorded completed response produces ordered translation events")
    func completedResponseProducesOrderedTranslation() throws {
        var decoder = OpenAIResponsesStreamDecoder(
            operation: .translate(targetLanguage: "es")
        )
        let payloads = [
            #"{"type":"response.created","response":{"id":"resp_123","status":"in_progress"}}"#,
            #"{"type":"response.output_text.delta","delta":"{\"source\":\"Hello\""}"#,
            #"{"type":"response.output_text.delta","delta":",\"translation\":\"Hola\"}"}"#,
            #"{"type":"response.completed","response":{"id":"resp_123","status":"completed","usage":{"input_tokens":15,"output_tokens":9,"total_tokens":24}}}"#,
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
                        requestID: "resp_123",
                        usage: ProviderTokenUsage(
                            inputTokens: 15,
                            outputTokens: 9,
                            totalTokens: 24
                        )
                    )
                ),
                .completed,
            ]
        )
    }

    @Test("an incomplete terminal response is rejected as truncated")
    func incompleteTerminalIsTruncated() {
        var decoder = OpenAIResponsesStreamDecoder(operation: .extractText)

        #expect(throws: ProviderAdapterError.outputTruncated) {
            _ = try decoder.consume(
                #"{"type":"response.incomplete","response":{"id":"resp_456","status":"incomplete"}}"#
            )
        }
    }
}
