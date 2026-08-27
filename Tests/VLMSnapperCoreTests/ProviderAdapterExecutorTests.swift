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
