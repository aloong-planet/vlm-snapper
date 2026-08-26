import Foundation

public struct OpenAIResponsesStreamDecoder: Sendable {
    private var structuredOutput: OrderedStructuredOutputParser
    private var responseID: String?
    private var completed = false

    public init(operation: ProviderOperation) {
        structuredOutput = OrderedStructuredOutputParser(operation: operation)
    }

    public mutating func consume(_ payload: String) throws -> [ProviderStreamEvent] {
        guard !completed else {
            throw ProviderAdapterError.incompleteResponse
        }
        let type: OpenAIEventType
        do {
            type = try JSONDecoder().decode(OpenAIEventType.self, from: Data(payload.utf8))
        } catch {
            throw ProviderAdapterError.incompleteResponse
        }
        switch type.type {
        case "response.created":
            let event = try decode(OpenAIResponseEvent.self, payload: payload)
            responseID = event.response.id
            return []
        case "response.output_text.delta":
            let event = try decode(OpenAITextDeltaEvent.self, payload: payload)
            do {
                return try structuredOutput.consume(event.delta)
            } catch {
                throw ProviderAdapterError.malformedOutput
            }
        case "response.completed":
            let event = try decode(OpenAIResponseEvent.self, payload: payload)
            guard event.response.status == "completed" else {
                throw ProviderAdapterError.incompleteResponse
            }
            do {
                try structuredOutput.finish()
            } catch {
                throw ProviderAdapterError.malformedOutput
            }
            completed = true
            let usage = event.response.usage.map {
                ProviderTokenUsage(
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    totalTokens: $0.totalTokens
                )
            }
            return [
                .metadata(
                    ProviderResponseMetadata(
                        requestID: event.response.id ?? responseID,
                        usage: usage
                    )
                ),
                .completed,
            ]
        case "response.incomplete":
            throw ProviderAdapterError.outputTruncated
        case "response.failed", "error":
            throw ProviderAdapterError.providerUnavailable
        default:
            return []
        }
    }

    public func finish() throws {
        guard completed else {
            throw ProviderAdapterError.incompleteResponse
        }
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        payload: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: Data(payload.utf8))
        } catch {
            throw ProviderAdapterError.incompleteResponse
        }
    }
}

private struct OpenAIEventType: Decodable {
    let type: String
}

private struct OpenAITextDeltaEvent: Decodable {
    let delta: String
}

private struct OpenAIResponseEvent: Decodable {
    let response: OpenAIResponse
}

private struct OpenAIResponse: Decodable {
    let id: String?
    let status: String
    let usage: OpenAIUsage?
}

private struct OpenAIUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}
