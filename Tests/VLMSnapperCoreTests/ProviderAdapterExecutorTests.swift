import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Provider adapter executor")
struct ProviderAdapterExecutorTests {
    @Test("A successful operation makes one request and streams normalized events")
    func successfulOperationMakesOneRequest() async throws {
        let transport = RecordingStreamingTransport(
            result: .success(
                ProviderHTTPStreamResponse(
                    statusCode: 200,
                    headers: [:],
                    body: stream([
                        sse("""
                        {"type":"response.output_text.delta","delta":"{\\\"source\\\":\\\"Hello\\\"}"}
                        """),
                        sse("""
                        {"type":"response.completed","response":{"id":"resp_1","status":"completed","usage":{"input_tokens":10,"output_tokens":2,"total_tokens":12}}}
                        """),
                    ])
                )
            )
        )
        let executor = ProviderAdapterExecutor(transport: transport)

        var events: [ProviderStreamEvent] = []
        for try await event in executor.stream(
            provider: .openAI,
            modelID: "gpt-4.1",
            apiKey: "secret",
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
            operation: .extractText
        ) {
            events.append(event)
        }

        #expect(await transport.requestCount == 1)
        #expect(events == [
            .sourceDelta("Hello"),
            .metadata(
                ProviderResponseMetadata(
                    requestID: "resp_1",
                    usage: ProviderTokenUsage(
                        inputTokens: 10,
                        outputTokens: 2,
                        totalTokens: 12
                    )
                )
            ),
            .completed,
        ])
    }

    @Test("A transport failure terminates after exactly one request")
    func transportFailureIsNotRetried() async {
        let transport = RecordingStreamingTransport(result: .failure(TestFailure.offline))
        let executor = ProviderAdapterExecutor(transport: transport)

        do {
            for try await _ in executor.stream(
                provider: .openAI,
                modelID: "gpt-4.1",
                apiKey: "secret",
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
                operation: .extractText
            ) {}
            Issue.record("Expected transport failure")
        } catch {
            #expect(error as? ProviderAdapterError == .transport)
        }
        #expect(await transport.requestCount == 1)
    }

    @Test("The first-text deadline terminates a silent stream")
    func firstTextDeadlineTerminatesSilentStream() async {
        let transport = RecordingStreamingTransport(
            result: .success(
                ProviderHTTPStreamResponse(
                    statusCode: 200,
                    headers: [:],
                    body: pendingStream()
                )
            )
        )
        let executor = ProviderAdapterExecutor(
            transport: transport,
            timeoutClock: RequestAwareTimeoutClock(transport: transport)
        )

        do {
            for try await _ in executor.stream(
                provider: .openAI,
                modelID: "gpt-4.1",
                apiKey: "secret",
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
                operation: .extractText
            ) {}
            Issue.record("Expected first-text timeout")
        } catch {
            #expect(error as? ProviderAdapterError == .firstTextTimeout)
        }
        #expect(await transport.requestCount == 1)
    }

    @Test("DeepSeek reasoning activity keeps the first-text deadline alive")
    func deepSeekReasoningKeepsFirstTextDeadlineAlive() async throws {
        // Deadlines expire only when the transport fires them, so host load cannot end the stream.
        let clock = ManualTimeoutClock()
        let executor = ProviderAdapterExecutor(
            transport: DeepSeekReasoningStreamingTransport(clock: clock),
            timeoutClock: clock
        )
        var events: [ProviderStreamEvent] = []

        for try await event in executor.stream(
            provider: .deepSeek,
            modelID: "deepseek-v4-flash-vision-exp",
            apiKey: "secret",
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
            operation: .extractText
        ) {
            events.append(event)
        }

        #expect(events == [
            .sourceDelta("Hello"),
            .metadata(ProviderResponseMetadata(requestID: "chat_reasoning", usage: nil)),
            .completed,
        ])
        // The request start and each reasoning event armed a first-text deadline.
        #expect(await clock.armIDs(of: .firstText).count == 3)
    }

    @Test("The stall deadline resets after text and terminates an idle stream")
    func stallDeadlineTerminatesAfterText() async {
        let transport = RecordingStreamingTransport(
            result: .success(
                ProviderHTTPStreamResponse(
                    statusCode: 200,
                    headers: [:],
                    body: streamThenPending([
                        sse("""
                        {"type":"response.output_text.delta","delta":"{\\\"source\\\":\\\"Hello"}
                        """),
                    ])
                )
            )
        )
        let executor = ProviderAdapterExecutor(
            transport: transport,
            timeoutClock: SelectiveTimeoutClock(immediateKind: .stalled)
        )
        var events: [ProviderStreamEvent] = []

        do {
            for try await event in executor.stream(
                provider: .openAI,
                modelID: "gpt-4.1",
                apiKey: "secret",
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
                operation: .extractText
            ) {
                events.append(event)
            }
            Issue.record("Expected stream-stall timeout")
        } catch {
            #expect(error as? ProviderAdapterError == .streamStalled)
        }
        #expect(events == [.sourceDelta("Hello")])
        #expect(await transport.requestCount == 1)
    }

    @Test("The total deadline terminates the whole operation")
    func totalDeadlineTerminatesOperation() async {
        let transport = RecordingStreamingTransport(
            result: .success(
                ProviderHTTPStreamResponse(
                    statusCode: 200,
                    headers: [:],
                    body: pendingStream()
                )
            )
        )
        let executor = ProviderAdapterExecutor(
            transport: transport,
            timeoutClock: SelectiveTimeoutClock(immediateKind: .total)
        )

        do {
            for try await _ in executor.stream(
                provider: .openAI,
                modelID: "gpt-4.1",
                apiKey: "secret",
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
                operation: .extractText
            ) {}
            Issue.record("Expected total timeout")
        } catch {
            #expect(error as? ProviderAdapterError == .totalTimeout)
        }
        #expect(await transport.requestCount <= 1)
    }

    @Test("Rate limits preserve a clamped Retry-After without retrying")
    func rateLimitIsNormalizedWithoutRetry() async {
        let transport = RecordingStreamingTransport(
            result: .success(
                ProviderHTTPStreamResponse(
                    statusCode: 429,
                    headers: ["retry-after": "900"],
                    body: stream([
                        Data("{\"error\":{\"code\":\"rate_limit_exceeded\"}}".utf8),
                    ])
                )
            )
        )
        let executor = ProviderAdapterExecutor(transport: transport)

        do {
            for try await _ in executor.stream(
                provider: .openAI,
                modelID: "gpt-4.1",
                apiKey: "secret",
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
                operation: .extractText
            ) {}
            Issue.record("Expected rate limit")
        } catch {
            #expect(
                error as? ProviderAdapterError
                    == .rateLimited(retryAfterSeconds: 300)
            )
        }
        #expect(await transport.requestCount == 1)
    }

    private func sse(_ payload: String) -> Data {
        Data("data: \(payload)\n\n".utf8)
    }

    private func stream(_ chunks: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    private func pendingStream() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { _ in }
    }

    private func streamThenPending(_ chunks: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
        }
    }
}

private enum TestFailure: Error {
    case offline
}

private actor RecordingStreamingTransport: ProviderHTTPStreaming {
    private(set) var requestCount = 0
    private let result: Result<ProviderHTTPStreamResponse, Error>

    init(result: Result<ProviderHTTPStreamResponse, Error>) {
        self.result = result
    }

    func stream(for request: URLRequest) async throws -> ProviderHTTPStreamResponse {
        requestCount += 1
        return try result.get()
    }
}

/// A DeepSeek stream of two reasoning events, then text. After each reasoning event it waits for
/// the first-text deadline that event re-arms, then fires every deadline armed before the event:
/// superseded ones are already cancelled, so firing them changes nothing, while one that survived
/// ends the stream with a first-text timeout.
private struct DeepSeekReasoningStreamingTransport: ProviderHTTPStreaming {
    let clock: ManualTimeoutClock

    func stream(for request: URLRequest) async throws -> ProviderHTTPStreamResponse {
        ProviderHTTPStreamResponse(
            statusCode: 200,
            headers: [:],
            body: AsyncThrowingStream { continuation in
                let producer = Task {
                    // The deadline armed when the request started.
                    await clock.waitForNewArm(of: .firstText, excluding: [])
                    for reasoning in ["Inspecting", "Reading"] {
                        let before = await clock.armIDs(of: .firstText)
                        continuation.yield(Self.sse(
                            #"{"id":"chat_reasoning","choices":[{"index":0,"delta":{"content":null,"reasoning_content":"\#(reasoning)"},"finish_reason":null}]}"#
                        ))
                        await clock.waitForNewArm(of: .firstText, excluding: before)
                        await clock.fire(before)
                        // Let a fired deadline that was still live reach the stream before text does.
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    continuation.yield(Self.sse(
                        #"{"id":"chat_reasoning","choices":[{"index":0,"delta":{"content":"{\"source\":\"Hello\"}"},"finish_reason":"stop"}]}"#
                    ))
                    continuation.yield(Self.sse("[DONE]"))
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    producer.cancel()
                }
            }
        )
    }

    private static func sse(_ payload: String) -> Data {
        Data("data: \(payload)\n\n".utf8)
    }
}

private struct SelectiveTimeoutClock: ProviderTimeoutClock {
    let immediateKind: ProviderTimeoutKind

    func sleep(for duration: Duration, kind: ProviderTimeoutKind) async throws {
        if kind == immediateKind {
            await Task.yield()
            return
        }
        try await Task.sleep(for: .seconds(3_600))
    }
}

private struct RequestAwareTimeoutClock: ProviderTimeoutClock {
    let transport: RecordingStreamingTransport

    func sleep(for duration: Duration, kind: ProviderTimeoutKind) async throws {
        guard kind == .firstText else {
            try await Task.sleep(for: .seconds(3_600))
            return
        }
        while await transport.requestCount == 0 {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}

/// A timeout clock whose sleeps end only when fired or cancelled, recording every deadline armed.
private actor ManualTimeoutClock: ProviderTimeoutClock {
    private var nextID = 0
    private var armed: [(id: Int, kind: ProviderTimeoutKind)] = []
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    private var cancelledBeforeSuspending: Set<Int> = []

    func sleep(for duration: Duration, kind: ProviderTimeoutKind) async throws {
        let id = nextID
        nextID += 1
        armed.append((id, kind))
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if cancelledBeforeSuspending.remove(id) != nil || Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func armIDs(of kind: ProviderTimeoutKind) -> Set<Int> {
        Set(armed.filter { $0.kind == kind }.map(\.id))
    }

    /// Waits until a deadline of `kind` outside `excluding` is armed; gives up after five seconds so
    /// a deadline that is never re-armed fails the test instead of hanging it.
    func waitForNewArm(of kind: ProviderTimeoutKind, excluding: Set<Int>) async {
        let giveUp = ContinuousClock.now.advanced(by: .seconds(5))
        while !armed.contains(where: { $0.kind == kind && !excluding.contains($0.id) }),
              ContinuousClock.now < giveUp {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Ends the given deadlines' sleeps as if they had expired; cancelled ones are no longer pending.
    func fire(_ ids: Set<Int>) {
        for id in ids {
            pending.removeValue(forKey: id)?.resume()
        }
    }

    private func cancel(_ id: Int) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        } else {
            cancelledBeforeSuspending.insert(id)
        }
    }
}
