import Foundation

public protocol OperationHistoryWriting: Sendable {
    func prepareOperation(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection,
        operation: ProviderOperation
    ) async throws -> PreparedOperation

    func markInFlight(
        operationID: UUID,
        as progress: OperationProgress
    ) async throws

    func finish(
        operationID: UUID,
        with outcome: PersistedOperationOutcome
    ) async throws

    func finish(
        operationID: UUID,
        with outcome: PersistedOperationOutcome,
        metrics: PersistedOperationMetrics
    ) async throws

    func finish(
        operationID: UUID,
        as completion: OperationCompletion
    ) async throws
}

public extension OperationHistoryWriting {
    func finish(
        operationID: UUID,
        with outcome: PersistedOperationOutcome,
        metrics: PersistedOperationMetrics
    ) async throws {
        try await finish(operationID: operationID, with: outcome)
    }
}

extension SQLiteHistoryStore: OperationHistoryWriting {}

extension SQLiteHistoryStore: HistoryRecordManaging {}

public protocol PreparedOperationStreaming: Sendable {
    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error>
}

public actor PersistedOperationWorkspaceRunner: OperationWorkspaceRunning {
    private struct PendingPersistence: Sendable {
        let operationID: UUID
        let outcome: PersistedOperationOutcome
        let metrics: PersistedOperationMetrics
        let result: WorkspaceCommittedResult
    }

    private let screenshotStore: any ScreenshotPersisting
    private let historyStore: any OperationHistoryWriting
    private let provider: any PreparedOperationStreaming
    private let now: @Sendable () -> Date
    private var managedScreenshot: ManagedScreenshot?
    private var pendingPersistence: PendingPersistence?

    public init(
        screenshotStore: any ScreenshotPersisting,
        historyStore: any OperationHistoryWriting,
        provider: any PreparedOperationStreaming,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.screenshotStore = screenshotStore
        self.historyStore = historyStore
        self.provider = provider
        self.now = now
    }

    public func run(
        originalPNG: Data,
        operation: ProviderOperation,
        selection: ProviderSelection
    ) async -> AsyncThrowingStream<OperationWorkspaceRunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.execute(
                    originalPNG: originalPNG,
                    operation: operation,
                    selection: selection,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func retrySavingResult() async throws -> WorkspaceCommittedResult {
        guard let pendingPersistence else {
            throw OperationWorkspaceSessionError.noUnsavedResult
        }
        try await historyStore.finish(
            operationID: pendingPersistence.operationID,
            with: pendingPersistence.outcome,
            metrics: pendingPersistence.metrics
        )
        self.pendingPersistence = nil
        return pendingPersistence.result
    }

    private func execute(
        originalPNG: Data,
        operation: ProviderOperation,
        selection: ProviderSelection,
        continuation: AsyncThrowingStream<OperationWorkspaceRunEvent, Error>
            .Continuation
    ) async {
        let startedAt = now()
        var firstTextAt: Date?
        var prepared: PreparedOperation?
        var unownedScreenshot: ManagedScreenshot?
        do {
            let persisted = try await persistedScreenshot(for: originalPNG)
            if persisted.isNew {
                unownedScreenshot = persisted.screenshot
            }
            let newPrepared = try await historyStore.prepareOperation(
                screenshot: persisted.screenshot,
                selection: selection,
                operation: operation
            )
            guard newPrepared.screenshot == persisted.screenshot,
                  newPrepared.selection == selection,
                  newPrepared.operation == operation
            else {
                throw OperationWorkspaceRunFailure(
                    code: "history_inconsistent"
                )
            }
            prepared = newPrepared
            unownedScreenshot = nil
            try await historyStore.markInFlight(
                operationID: newPrepared.operationID,
                as: .uploading
            )
            let stream = await provider.stream(
                originalPNG: originalPNG,
                preparedOperation: newPrepared
            )
            try await historyStore.markInFlight(
                operationID: newPrepared.operationID,
                as: .streaming
            )
            var accumulator = ProviderStreamAccumulator(operation: operation)
            var completed = false
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case let .sourceDelta(delta):
                    if firstTextAt == nil, !delta.isEmpty { firstTextAt = now() }
                    continuation.yield(.sourceDelta(delta))
                case let .translationDelta(delta):
                    if firstTextAt == nil, !delta.isEmpty { firstTextAt = now() }
                    continuation.yield(.translationDelta(delta))
                case .metadata, .completed:
                    break
                }
                if let output = try accumulator.consume(event) {
                    let result = WorkspaceCommittedResult(
                        sourceMarkdown: output.source,
                        translationMarkdown: output.translation
                    )
                    let outcome = PersistedOperationOutcome.succeeded(
                        sourceMarkdown: output.source,
                        translationMarkdown: output.translation
                    )
                    let metrics = PersistedOperationMetrics(
                        firstTextLatencyMilliseconds: firstTextAt.map {
                            Self.milliseconds(from: startedAt, to: $0)
                        },
                        totalLatencyMilliseconds: Self.milliseconds(from: startedAt, to: now()),
                        usage: output.metadata.usage
                    )
                    do {
                        try await historyStore.finish(
                            operationID: newPrepared.operationID,
                            with: outcome,
                            metrics: metrics
                        )
                        continuation.yield(.succeeded(result))
                    } catch {
                        pendingPersistence = PendingPersistence(
                            operationID: newPrepared.operationID,
                            outcome: outcome,
                            metrics: metrics,
                            result: result
                        )
                        try? await historyStore.finish(
                            operationID: newPrepared.operationID,
                            as: .resultPersistenceFailed
                        )
                        continuation.yield(.resultPersistenceFailed(result))
                    }
                    completed = true
                }
            }
            guard completed else {
                throw ProviderStreamContractError.incompleteOutput
            }
            continuation.finish()
        } catch {
            let isCancellation = error is CancellationError
                || (error as? ProviderAdapterError) == .cancelled
            if let unownedScreenshot {
                managedScreenshot = nil
                try? await screenshotStore.discardIfOwned(unownedScreenshot)
            }
            if isCancellation {
                if let prepared {
                    try? await historyStore.finish(
                        operationID: prepared.operationID,
                        as: .canceled
                    )
                }
                continuation.finish(throwing: CancellationError())
                return
            }
            let failureCode: String
            if let runFailure = error as? OperationWorkspaceRunFailure {
                failureCode = runFailure.code
            } else if let adapterError = error as? ProviderAdapterError {
                failureCode = adapterError.normalizedCode
            } else if error is ProviderStreamContractError {
                failureCode = "incomplete_response"
            } else {
                failureCode = "operation_failed"
            }
            if let prepared {
                try? await historyStore.finish(
                    operationID: prepared.operationID,
                    with: .failed(normalizedErrorCode: failureCode),
                    metrics: PersistedOperationMetrics(
                        firstTextLatencyMilliseconds: firstTextAt.map {
                            Self.milliseconds(from: startedAt, to: $0)
                        },
                        totalLatencyMilliseconds: Self.milliseconds(from: startedAt, to: now())
                    )
                )
            }
            continuation.finish(
                throwing: OperationWorkspaceRunFailure(code: failureCode)
            )
        }
    }

    private func persistedScreenshot(
        for originalPNG: Data
    ) async throws -> (screenshot: ManagedScreenshot, isNew: Bool) {
        if let managedScreenshot {
            return (managedScreenshot, false)
        }
        let screenshot = try await screenshotStore.save(originalPNG: originalPNG)
        managedScreenshot = screenshot
        return (screenshot, true)
    }

    private static func milliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }
}
