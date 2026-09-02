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

    @Test("the observed text field is normalized for extraction")
    func observedTextFieldIsNormalizedForExtraction() throws {
        var decoder = DeepSeekChatStreamDecoder(operation: .extractText)
        let payloads = [
            #"{"id":"chat_extract","choices":[{"index":0,"delta":{"content":"{\"text\":\"Captured"},"finish_reason":null}]}"#,
            #"{"id":"chat_extract","choices":[{"index":0,"delta":{"content":" text\"}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":20,"completion_tokens":4,"total_tokens":24}}"#,
            "[DONE]",
        ]
        var events: [ProviderStreamEvent] = []

        for payload in payloads {
            events.append(contentsOf: try decoder.consume(payload))
        }
        try decoder.finish()

        #expect(events == [
            .sourceDelta("Captured"),
            .sourceDelta(" text"),
            .metadata(
                ProviderResponseMetadata(
                    requestID: "chat_extract",
                    usage: ProviderTokenUsage(
                        inputTokens: 20,
                        outputTokens: 4,
                        totalTokens: 24
                    )
                )
            ),
            .completed,
        ])
    }

    @Test("only nonempty reasoning is reported as private provider activity")
    func onlyNonemptyReasoningIsPrivateProviderActivity() throws {
        var decoder = DeepSeekChatStreamDecoder(operation: .extractText)

        let reasoningEvents = try decoder.consume(
            #"{"id":"chat_reasoning","choices":[{"index":0,"delta":{"content":null,"reasoning_content":"Inspecting"},"finish_reason":null}]}"#
        )
        #expect(reasoningEvents.isEmpty)
        #expect(decoder.lastPayloadContainedReasoningActivity)

        let bufferedContentEvents = try decoder.consume(
            #"{"id":"chat_reasoning","choices":[{"index":0,"delta":{"content":"{"},"finish_reason":null}]}"#
        )
        #expect(bufferedContentEvents.isEmpty)
        #expect(!decoder.lastPayloadContainedReasoningActivity)

        let emptyReasoningEvents = try decoder.consume(
            #"{"id":"chat_reasoning","choices":[{"index":0,"delta":{"content":null,"reasoning_content":""},"finish_reason":null}]}"#
        )
        #expect(emptyReasoningEvents.isEmpty)
        #expect(!decoder.lastPayloadContainedReasoningActivity)
    }

    @Test("the text alias remains invalid for translation")
    func textAliasRemainsInvalidForTranslation() {
        var decoder = DeepSeekChatStreamDecoder(
            operation: .translate(targetLanguage: "es")
        )

        #expect(throws: ProviderAdapterError.malformedOutput) {
            _ = try decoder.consume(
                #"{"id":"chat_translate","choices":[{"index":0,"delta":{"content":"{\"text\":\"Hello\",\"translation\":\"Hola\"}"},"finish_reason":"stop"}]}"#
            )
        }
    }

    @Test("the extraction alias does not permit extra fields")
    func extractionAliasDoesNotPermitExtraFields() {
        var decoder = DeepSeekChatStreamDecoder(operation: .extractText)

        #expect(throws: ProviderAdapterError.malformedOutput) {
            _ = try decoder.consume(
                #"{"id":"chat_extract","choices":[{"index":0,"delta":{"content":"{\"text\":\"Hello\",\"extra\":true}"},"finish_reason":"stop"}]}"#
            )
        }
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
