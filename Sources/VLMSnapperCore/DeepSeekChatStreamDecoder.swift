import Foundation

public struct DeepSeekChatStreamDecoder: Sendable {
    private var structuredOutput: OrderedStructuredOutputParser
    private var responseID: String?
    private var usage: ProviderTokenUsage?
    private var receivedStop = false
    private var receivedDone = false

    public init(operation: ProviderOperation) {
        structuredOutput = OrderedStructuredOutputParser(operation: operation)
    }

    public mutating func consume(_ payload: String) throws -> [ProviderStreamEvent] {
        guard !receivedDone else {
            throw ProviderAdapterError.incompleteResponse
        }
        if payload == "[DONE]" {
            guard receivedStop else {
                throw ProviderAdapterError.incompleteResponse
            }
            receivedDone = true
            return [
                .metadata(
                    ProviderResponseMetadata(
                        requestID: responseID,
                        usage: usage
                    )
                ),
                .completed,
            ]
        }
        let chunk: DeepSeekChatChunk
        do {
            chunk = try JSONDecoder().decode(
                DeepSeekChatChunk.self,
                from: Data(payload.utf8)
            )
        } catch {
            throw ProviderAdapterError.incompleteResponse
        }
        responseID = chunk.id
        if let currentUsage = chunk.usage {
            usage = ProviderTokenUsage(
                inputTokens: currentUsage.promptTokens,
                outputTokens: currentUsage.completionTokens,
                totalTokens: currentUsage.totalTokens
            )
        }
        var events: [ProviderStreamEvent] = []
        if let choice = chunk.choices.first(where: { $0.index == 0 }) {
            if let content = choice.delta.content, !content.isEmpty {
                do {
                    events.append(contentsOf: try structuredOutput.consume(content))
                } catch {
                    throw ProviderAdapterError.malformedOutput
                }
            }
            if let finishReason = choice.finishReason {
                try accept(finishReason: finishReason)
            }
        }
        return events
    }

    public func finish() throws {
        guard receivedDone else {
            throw ProviderAdapterError.incompleteResponse
        }
    }

    private mutating func accept(finishReason: String) throws {
        switch finishReason {
        case "stop":
            do {
                try structuredOutput.finish()
            } catch {
                throw ProviderAdapterError.malformedOutput
            }
            receivedStop = true
        case "length":
            throw ProviderAdapterError.outputTruncated
        case "content_filter":
            throw ProviderAdapterError.contentBlocked
        case "insufficient_system_resource":
            throw ProviderAdapterError.providerUnavailable
        default:
            throw ProviderAdapterError.incompleteResponse
        }
    }
}

private struct DeepSeekChatChunk: Decodable {
    let id: String
    let choices: [DeepSeekChoice]
    let usage: DeepSeekUsage?
}

private struct DeepSeekChoice: Decodable {
    let index: Int
    let delta: DeepSeekDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }
}

private struct DeepSeekDelta: Decodable {
    let content: String?
}

private struct DeepSeekUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
