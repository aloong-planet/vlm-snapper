import Foundation

public struct ProviderHTTPStreamResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: AsyncThrowingStream<Data, Error>

    public init(
        statusCode: Int,
        headers: [String: String],
        body: AsyncThrowingStream<Data, Error>
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol ProviderHTTPStreaming: Sendable {
    func stream(for request: URLRequest) async throws -> ProviderHTTPStreamResponse
}

public struct URLSessionProviderHTTPStreamer: ProviderHTTPStreaming {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func stream(for request: URLRequest) async throws -> ProviderHTTPStreamResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderAdapterError.transport
        }
        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) {
            partialResult, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else {
                return
            }
            partialResult[key.lowercased()] = value
        }
        let body = AsyncThrowingStream<Data, Error> { continuation in
            let producer = Task {
                do {
                    var chunk = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunk.append(byte)
                        if byte == 0x0A || chunk.count >= 4_096 {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ProviderAdapterError.cancelled)
                } catch {
                    continuation.finish(throwing: ProviderAdapterError.transport)
                }
            }
            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
        return ProviderHTTPStreamResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: body
        )
    }
}
