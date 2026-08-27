import Foundation

public struct GeminiStreamDecoder: Sendable {
    private var structuredOutput: OrderedStructuredOutputParser
    private var responseID: String?
    private var inputTokens: Int?
    private var outputTokens: Int?
    private var totalTokens: Int?
    private var receivedStop = false

    public init(operation: ProviderOperation) {
        structuredOutput = OrderedStructuredOutputParser(operation: operation)
    }

    public mutating func consume(_ payload: String) throws -> [ProviderStreamEvent] {
        let response: GeminiGenerateContentResponse
        do {
            response = try JSONDecoder().decode(
                GeminiGenerateContentResponse.self,
                from: Data(payload.utf8)
            )
        } catch {
            throw ProviderAdapterError.incompleteResponse
        }
        if response.promptFeedback?.blockReason != nil {
            throw ProviderAdapterError.contentBlocked
        }
        if let currentResponseID = response.responseID {
            responseID = currentResponseID
        }
        if let currentUsage = response.usageMetadata {
            inputTokens = currentUsage.promptTokenCount ?? inputTokens
            outputTokens = currentUsage.candidatesTokenCount ?? outputTokens
            totalTokens = currentUsage.totalTokenCount ?? totalTokens
        }
        if receivedStop {
            let hasMoreCandidateData = response.candidates?.contains { candidate in
                candidate.finishReason != nil ||
                    (candidate.content?.parts ?? []).contains { $0.text != nil }
            } ?? false
            guard !hasMoreCandidateData else {
                throw ProviderAdapterError.incompleteResponse
            }
            return []
        }
        var events: [ProviderStreamEvent] = []
        if let candidate = response.candidates?.first(where: { $0.index == 0 }) {
            for part in candidate.content?.parts ?? [] {
                guard let text = part.text else {
                    continue
                }
                do {
                    events.append(contentsOf: try structuredOutput.consume(text))
                } catch {
                    throw ProviderAdapterError.malformedOutput
                }
            }
            if let finishReason = candidate.finishReason {
                try accept(finishReason: finishReason)
            }
        }
        return events
    }

    public mutating func finish() throws -> [ProviderStreamEvent] {
        guard receivedStop else {
            throw ProviderAdapterError.incompleteResponse
        }
        return [
            .metadata(
                ProviderResponseMetadata(
                    requestID: responseID,
                    usage: completeUsage
                )
            ),
            .completed,
        ]
    }

    private var completeUsage: ProviderTokenUsage? {
        guard let inputTokens, let outputTokens, let totalTokens else {
            return nil
        }
        return ProviderTokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens
        )
    }

    private mutating func accept(finishReason: String) throws {
        switch finishReason {
        case "STOP":
            do {
                try structuredOutput.finish()
            } catch {
                throw ProviderAdapterError.malformedOutput
            }
            receivedStop = true
        case "MAX_TOKENS":
            throw ProviderAdapterError.outputTruncated
        case "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII",
             "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT", "IMAGE_RECITATION":
            throw ProviderAdapterError.contentBlocked
        default:
            throw ProviderAdapterError.providerUnavailable
        }
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let promptFeedback: GeminiPromptFeedback?
    let usageMetadata: GeminiUsageMetadata?
    let responseID: String?

    enum CodingKeys: String, CodingKey {
        case candidates
        case promptFeedback
        case usageMetadata
        case responseID = "responseId"
    }
}

private struct GeminiCandidate: Decodable {
    let index: Int
    let content: GeminiContent?
    let finishReason: String?
}

private struct GeminiContent: Decodable {
    let parts: [GeminiPart]?
}

private struct GeminiPart: Decodable {
    let text: String?
}

private struct GeminiPromptFeedback: Decodable {
    let blockReason: String?
}

private struct GeminiUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
}
