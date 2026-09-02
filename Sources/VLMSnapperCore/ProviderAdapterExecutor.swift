import Foundation

public struct ProviderAdapterExecutor: Sendable {
    private let transport: any ProviderHTTPStreaming
    private let requestFactory: ProviderRequestFactory
    private let errorNormalizer: ProviderHTTPErrorNormalizer
    private let timeoutClock: any ProviderTimeoutClock
    private let timeouts: ProviderStreamTimeouts

    public init(
        transport: any ProviderHTTPStreaming = URLSessionProviderHTTPStreamer(),
        requestFactory: ProviderRequestFactory = ProviderRequestFactory(),
        errorNormalizer: ProviderHTTPErrorNormalizer = ProviderHTTPErrorNormalizer(),
        timeoutClock: any ProviderTimeoutClock = ContinuousProviderTimeoutClock(),
        timeouts: ProviderStreamTimeouts = ProviderStreamTimeouts()
    ) {
        self.transport = transport
        self.requestFactory = requestFactory
        self.errorNormalizer = errorNormalizer
        self.timeoutClock = timeoutClock
        self.timeouts = timeouts
    }

    public func stream(
        provider: ProviderID,
        modelID: String,
        apiKey: String,
        originalPNG: Data,
        operation: ProviderOperation
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let coordinator = ProviderStreamTimeoutCoordinator(
                continuation: continuation,
                clock: timeoutClock,
                timeouts: timeouts
            )
            let task = Task {
                await coordinator.startTotal()
                do {
                    let request = try requestFactory.makeRequest(
                        provider: provider,
                        modelID: modelID,
                        apiKey: apiKey,
                        originalPNG: originalPNG,
                        operation: operation
                    )
                    await coordinator.startFirstText()
                    let response: ProviderHTTPStreamResponse
                    do {
                        response = try await transport.stream(for: request)
                    } catch is CancellationError {
                        throw ProviderAdapterError.cancelled
                    } catch let error as ProviderAdapterError {
                        throw error
                    } catch {
                        throw ProviderAdapterError.transport
                    }
                    try await validateHTTP(provider: provider, response: response)
                    var sseDecoder = ServerSentEventDecoder()
                    var providerDecoder = ProviderWireStreamDecoder(
                        provider: provider,
                        operation: operation
                    )
                    for try await chunk in response.body {
                        try Task.checkCancellation()
                        for payload in try sseDecoder.consume(chunk) {
                            let decoded = try providerDecoder.consume(payload)
                            if decoded.containsActivity {
                                await coordinator.receivedActivity(
                                    includesText: decoded.containsText
                                )
                            }
                            for event in decoded.events {
                                continuation.yield(event)
                            }
                        }
                    }
                    try sseDecoder.finish()
                    for event in try providerDecoder.finish() {
                        continuation.yield(event)
                    }
                    await coordinator.complete()
                } catch is CancellationError {
                    await coordinator.fail(.cancelled)
                } catch let error as ProviderAdapterError {
                    await coordinator.fail(error)
                } catch is ServerSentEventDecoderError {
                    await coordinator.fail(.incompleteResponse)
                } catch {
                    await coordinator.fail(.transport)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func validateHTTP(
        provider: ProviderID,
        response: ProviderHTTPStreamResponse
    ) async throws {
        guard !(200..<300).contains(response.statusCode) else {
            return
        }
        var body = Data()
        let maximumErrorBodyBytes = 65_536
        for try await chunk in response.body {
            let available = maximumErrorBodyBytes - body.count
            guard available > 0 else {
                break
            }
            body.append(chunk.prefix(available))
        }
        throw errorNormalizer.normalize(
            provider: provider,
            statusCode: response.statusCode,
            headers: response.headers,
            body: body
        )
    }
}

private extension ProviderStreamEvent {
    var containsText: Bool {
        switch self {
        case let .sourceDelta(delta), let .translationDelta(delta):
            return !delta.isEmpty
        case .metadata, .completed:
            return false
        }
    }
}

private enum ProviderWireStreamDecoder {
    case openAI(OpenAIResponsesStreamDecoder)
    case gemini(GeminiStreamDecoder)
    case deepSeek(DeepSeekChatStreamDecoder)

    init(provider: ProviderID, operation: ProviderOperation) {
        switch provider {
        case .openAI:
            self = .openAI(OpenAIResponsesStreamDecoder(operation: operation))
        case .gemini:
            self = .gemini(GeminiStreamDecoder(operation: operation))
        case .deepSeek:
            self = .deepSeek(DeepSeekChatStreamDecoder(operation: operation))
        }
    }

    mutating func consume(_ payload: String) throws -> ProviderWireDecodeResult {
        switch self {
        case var .openAI(decoder):
            let events = try decoder.consume(payload)
            self = .openAI(decoder)
            return ProviderWireDecodeResult(events: events)
        case var .gemini(decoder):
            let events = try decoder.consume(payload)
            self = .gemini(decoder)
            return ProviderWireDecodeResult(events: events)
        case var .deepSeek(decoder):
            let events = try decoder.consume(payload)
            self = .deepSeek(decoder)
            return ProviderWireDecodeResult(
                events: events,
                containsProviderActivity: decoder.lastPayloadContainedReasoningActivity
            )
        }
    }

    mutating func finish() throws -> [ProviderStreamEvent] {
        switch self {
        case let .openAI(decoder):
            try decoder.finish()
            return []
        case var .gemini(decoder):
            let events = try decoder.finish()
            self = .gemini(decoder)
            return events
        case let .deepSeek(decoder):
            try decoder.finish()
            return []
        }
    }
}

private struct ProviderWireDecodeResult {
    let events: [ProviderStreamEvent]
    let containsProviderActivity: Bool

    init(
        events: [ProviderStreamEvent],
        containsProviderActivity: Bool = false
    ) {
        self.events = events
        self.containsProviderActivity = containsProviderActivity
    }

    var containsText: Bool {
        events.contains { $0.containsText }
    }

    var containsActivity: Bool {
        containsProviderActivity || containsText
    }
}
