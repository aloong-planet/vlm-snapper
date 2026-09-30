import Foundation

public struct ProviderPreparedOperationStreamer: PreparedOperationStreaming {
    private let credentialStore: any ProviderCredentialStoring
    private let executor: ProviderAdapterExecutor

    public init(
        credentialStore: any ProviderCredentialStoring,
        executor: ProviderAdapterExecutor = ProviderAdapterExecutor()
    ) {
        self.credentialStore = credentialStore
        self.executor = executor
    }

    public func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        guard let provider = ProviderID(
            rawValue: preparedOperation.selection.providerID
        ) else {
            return failedStream(ProviderAdapterError.modelUnavailable)
        }
        do {
            guard let credential = try await credentialStore.credential(
                for: provider
            ) else {
                return failedStream(ProviderAdapterError.invalidCredential)
            }
            return executor.stream(
                provider: provider,
                modelID: preparedOperation.selection.modelID,
                apiKey: credential.apiKey,
                originalPNG: originalPNG,
                operation: preparedOperation.operation,
                sourceSegments: preparedOperation.sourceSegments
            )
        } catch {
            return failedStream(error)
        }
    }

    private func failedStream(
        _ error: Error
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}
