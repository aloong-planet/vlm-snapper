import Testing
@testable import VLMSnapperCore

@Suite("Gemini stream decoder")
struct GeminiStreamDecoderTests {
    @Test("a recorded STOP stream completes only after clean EOF")
    func stopStreamCompletesAtCleanEOF() throws {
        var decoder = GeminiStreamDecoder(
            operation: .translate(targetLanguage: "es")
        )
        let payloads = [
            #"{"responseId":"gem_123","candidates":[{"index":0,"content":{"parts":[{"text":"{\"source\":\"Hello\""}]}}]}"#,
            #"{"responseId":"gem_123","candidates":[{"index":0,"content":{"parts":[{"text":",\"translation\":\"Hola\"}"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":11,"candidatesTokenCount":7,"totalTokenCount":18}}"#,
        ]
        var events: [ProviderStreamEvent] = []

        for payload in payloads {
            events.append(contentsOf: try decoder.consume(payload))
        }
        #expect(!events.contains(.completed))
        events.append(contentsOf: try decoder.finish())

        #expect(
            events == [
                .sourceDelta("Hello"),
                .translationDelta("Hola"),
                .metadata(
                    ProviderResponseMetadata(
                        requestID: "gem_123",
                        usage: ProviderTokenUsage(
                            inputTokens: 11,
                            outputTokens: 7,
                            totalTokens: 18
                        )
                    )
                ),
                .completed,
            ]
        )
    }

    @Test("usage metadata may arrive after STOP before clean EOF")
    func acceptsUsageAfterStop() throws {
        var decoder = GeminiStreamDecoder(operation: .extractText)
        var events = try decoder.consume(
            #"{"responseId":"gem_456","candidates":[{"index":0,"content":{"parts":[{"text":"{\"source\":\"Hello\"}"}]},"finishReason":"STOP"}]}"#
        )
        events.append(contentsOf: try decoder.consume(
            #"{"responseId":"gem_456","usageMetadata":{"promptTokenCount":8,"candidatesTokenCount":3,"totalTokenCount":11}}"#
        ))
        events.append(contentsOf: try decoder.finish())

        #expect(events == [
            .sourceDelta("Hello"),
            .metadata(
                ProviderResponseMetadata(
                    requestID: "gem_456",
                    usage: ProviderTokenUsage(
                        inputTokens: 8,
                        outputTokens: 3,
                        totalTokens: 11
                    )
                )
            ),
            .completed,
        ])
    }

    @Test("MAX_TOKENS is rejected as truncated")
    func maxTokensIsTruncated() {
        var decoder = GeminiStreamDecoder(operation: .extractText)

        #expect(throws: ProviderAdapterError.outputTruncated) {
            _ = try decoder.consume(
                #"{"candidates":[{"index":0,"finishReason":"MAX_TOKENS"}]}"#
            )
        }
    }

    @Test("partial usage metadata does not invalidate a completed response")
    func partialUsageDoesNotInvalidateResponse() throws {
        var decoder = GeminiStreamDecoder(operation: .extractText)
        var events = try decoder.consume(
            #"{"responseId":"gem_789","candidates":[{"index":0,"content":{"parts":[{"text":"{\"source\":\"Hello\"}"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":8,"totalTokenCount":11}}"#
        )
        events.append(contentsOf: try decoder.finish())

        #expect(events == [
            .sourceDelta("Hello"),
            .metadata(ProviderResponseMetadata(requestID: "gem_789", usage: nil)),
            .completed,
        ])
    }
}
