import Foundation

public protocol OperationHistoryWriting: Sendable {
    func operation(id: UUID) async throws -> StoredOperation?

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

    func replace(
        operationID: UUID,
        selection: ProviderSelection,
        operation: ProviderOperation,
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

/// Keeps what a request showed about a model's image input (v1-core failure mode 10).
public protocol VisionCompatibilityRecording: Sendable {
    func recordVisionSuccess(provider: ProviderID, modelID: String) async throws

    func recordVisionFailure(
        provider: ProviderID,
        modelID: String,
        evidence: VisionFailureEvidence
    ) async throws
}

extension ProviderConfigurationCoordinator: VisionCompatibilityRecording {}

public actor PersistedOperationWorkspaceRunner: OperationWorkspaceRunning {
    private struct PendingPersistence: Sendable {
        let preparedOperation: PreparedOperation
        let replacesExistingResult: Bool
        let outcome: PersistedOperationOutcome
        let metrics: PersistedOperationMetrics
        let result: WorkspaceCommittedResult
    }

    private enum OperationSlot: Hashable, Sendable {
        case extract
        case translate
    }

    private let screenshotStore: any ScreenshotPersisting & ManagedScreenshotLoading
    private let historyStore: any OperationHistoryWriting
    private let provider: any PreparedOperationStreaming
    private let visionCompatibility: (any VisionCompatibilityRecording)?
    private let now: @Sendable () -> Date
    private var managedScreenshot: ManagedScreenshot?
    private var preparedOperations: [OperationSlot: PreparedOperation] = [:]
    private var pendingPersistence: PendingPersistence?
    private var activeRun: Task<Void, Never>?
    /// A runner opened on an existing record stays bound to it, whatever a run asks for (v1-core::REQ-002/AC-03).
    private let isBoundToRestoredRecord: Bool

    public init(
        screenshotStore: any ScreenshotPersisting & ManagedScreenshotLoading,
        historyStore: any OperationHistoryWriting,
        provider: any PreparedOperationStreaming,
        visionCompatibility: (any VisionCompatibilityRecording)? = nil,
        restoring operation: StoredOperation? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.screenshotStore = screenshotStore
        self.historyStore = historyStore
        self.provider = provider
        self.visionCompatibility = visionCompatibility
        self.now = now
        isBoundToRestoredRecord = operation != nil
        if let operation {
            managedScreenshot = operation.screenshot
            let restoredOperation: ProviderOperation = operation.kind == .extract
                ? .extractText
                : .translate(targetLanguage: operation.targetLanguage ?? "")
            preparedOperations[Self.slot(for: restoredOperation)] = PreparedOperation(
                operationID: operation.id,
                screenshot: operation.screenshot,
                selection: operation.selection,
                operation: restoredOperation
            )
        }
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
            activeRun = task
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func waitForRunToFinish() async {
        await activeRun?.value
    }

    public func retrySavingResult() async throws -> WorkspaceCommittedResult {
        guard let pendingPersistence else {
            throw OperationWorkspaceSessionError.noUnsavedResult
        }
        try await persist(
            pendingPersistence.outcome,
            metrics: pendingPersistence.metrics,
            preparedOperation: pendingPersistence.preparedOperation,
            replacesExistingResult: pendingPersistence.replacesExistingResult
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
        var replacesExistingResult = false
        var unownedScreenshot: ManagedScreenshot?
        do {
            let persisted = try await persistedScreenshot(for: originalPNG)
            if persisted.isNew {
                unownedScreenshot = persisted.screenshot
            }
            let slot = Self.slot(for: operation)
            let newPrepared: PreparedOperation
            // The same operation is a rerun of its record; another target language is a new
            // translation with its own record (v1-core::REQ-011/AC-06).
            if let existing = preparedOperations[slot],
               isBoundToRestoredRecord || existing.operation == operation {
                guard let stored = try await historyStore.operation(id: existing.operationID),
                      stored.screenshot == existing.screenshot,
                      !stored.status.isActive else {
                    throw OperationWorkspaceRunFailure(code: "history_record_unavailable")
                }
                switch existing.operation {
                case .extractText:
                    guard stored.kind == .extract else {
                        throw OperationWorkspaceRunFailure(code: "history_record_unavailable")
                    }
                case let .translate(language):
                    guard !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          stored.kind == .translate, stored.targetLanguage == language else {
                        throw OperationWorkspaceRunFailure(code: "history_record_unavailable")
                    }
                }
                newPrepared = PreparedOperation(
                    operationID: existing.operationID,
                    screenshot: persisted.screenshot,
                    selection: selection,
                    operation: existing.operation
                )
                replacesExistingResult = true
            } else {
                newPrepared = try await historyStore.prepareOperation(
                    screenshot: persisted.screenshot,
                    selection: selection,
                    operation: operation
                )
            }
            guard newPrepared.screenshot == persisted.screenshot,
                  newPrepared.selection == selection,
                  Self.slot(for: newPrepared.operation) == slot
            else {
                throw OperationWorkspaceRunFailure(
                    code: "history_inconsistent"
                )
            }
            prepared = newPrepared
            unownedScreenshot = nil
            preparedOperations[slot] = newPrepared
            if !replacesExistingResult {
                try await historyStore.markInFlight(
                    operationID: newPrepared.operationID,
                    as: .uploading
                )
            }
            try Task.checkCancellation()
            let stream = await provider.stream(
                originalPNG: originalPNG,
                preparedOperation: newPrepared
            )
            if !replacesExistingResult {
                try await historyStore.markInFlight(
                    operationID: newPrepared.operationID,
                    as: .streaming
                )
            }
            var accumulator = ProviderStreamAccumulator(operation: newPrepared.operation)
            var completed = false
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case let .translationSegments(segments):
                    if firstTextAt == nil, segments.contains(where: { !$0.source.isEmpty || !$0.translation.isEmpty }) {
                        firstTextAt = now()
                    }
                    continuation.yield(.translationSegments(segments))
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
                    await recordVisionSuccess(for: newPrepared.selection)
                    let result = WorkspaceCommittedResult(
                        sourceMarkdown: output.source,
                        translationMarkdown: output.translation,
                        segments: output.segments
                    )
                    let outcome = PersistedOperationOutcome.succeeded(
                        sourceMarkdown: output.source,
                        translationMarkdown: output.translation,
                        segments: output.segments
                    )
                    let metrics = PersistedOperationMetrics(
                        firstTextLatencyMilliseconds: firstTextAt.map {
                            Self.milliseconds(from: startedAt, to: $0)
                        },
                        totalLatencyMilliseconds: Self.milliseconds(from: startedAt, to: now()),
                        usage: output.metadata.usage
                    )
                    do {
                        try await persist(
                            outcome,
                            metrics: metrics,
                            preparedOperation: newPrepared,
                            replacesExistingResult: replacesExistingResult
                        )
                        continuation.yield(.succeeded(result))
                    } catch {
                        pendingPersistence = PendingPersistence(
                            preparedOperation: newPrepared,
                            replacesExistingResult: replacesExistingResult,
                            outcome: outcome,
                            metrics: metrics,
                            result: result
                        )
                        if !replacesExistingResult {
                            try? await historyStore.finish(
                                operationID: newPrepared.operationID,
                                as: .resultPersistenceFailed
                            )
                        }
                        continuation.yield(.resultPersistenceFailed(result,
                            code: (error as? OperationWorkspaceRunFailure)?.code))
                    }
                    completed = true
                }
            }
            // A canceled task ends the provider's stream without an error, which is not an incomplete response.
            try Task.checkCancellation()
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
                if let prepared, !replacesExistingResult {
                    try? await historyStore.finish(
                        operationID: prepared.operationID,
                        as: .canceled
                    )
                }
                continuation.finish(throwing: CancellationError())
                return
            }
            if let prepared, (error as? ProviderAdapterError) == .imageInputUnsupported {
                await recordVisionFailure(for: prepared.selection)
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
            if let prepared, !replacesExistingResult {
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

    // A request's outcome stands whether or not this can be noted, so a failure here changes nothing.
    private func recordVisionSuccess(for selection: ProviderSelection) async {
        guard let provider = ProviderID(rawValue: selection.providerID) else { return }
        try? await visionCompatibility?.recordVisionSuccess(provider: provider, modelID: selection.modelID)
    }

    private func recordVisionFailure(for selection: ProviderSelection) async {
        guard let provider = ProviderID(rawValue: selection.providerID) else { return }
        try? await visionCompatibility?.recordVisionFailure(
            provider: provider,
            modelID: selection.modelID,
            evidence: .imageInputUnsupported
        )
    }

    private func persistedScreenshot(
        for originalPNG: Data
    ) async throws -> (screenshot: ManagedScreenshot, isNew: Bool) {
        if let managedScreenshot {
            do {
                let savedPNG = try await screenshotStore.loadIfOwned(managedScreenshot)
                guard savedPNG == originalPNG else {
                    throw ScreenshotStoreError.ownershipMismatch
                }
            } catch {
                throw OperationWorkspaceRunFailure(code: "history_screenshot_unavailable")
            }
            return (managedScreenshot, false)
        }
        let screenshot: ManagedScreenshot
        do {
            screenshot = try await screenshotStore.save(originalPNG: originalPNG)
        } catch {
            throw OperationWorkspaceRunFailure(code: "screenshot_save_failed")
        }
        managedScreenshot = screenshot
        return (screenshot, true)
    }

    private func persist(
        _ outcome: PersistedOperationOutcome,
        metrics: PersistedOperationMetrics,
        preparedOperation: PreparedOperation,
        replacesExistingResult: Bool
    ) async throws {
        if replacesExistingResult {
            do {
                try await historyStore.replace(
                    operationID: preparedOperation.operationID,
                    selection: preparedOperation.selection,
                    operation: preparedOperation.operation,
                    with: outcome,
                    metrics: metrics
                )
            } catch SQLiteHistoryStoreError.operationNotFound {
                throw OperationWorkspaceRunFailure(code: "history_record_unavailable")
            }
        } else {
            try await historyStore.finish(
                operationID: preparedOperation.operationID,
                with: outcome,
                metrics: metrics
            )
        }
    }

    private static func slot(for operation: ProviderOperation) -> OperationSlot {
        switch operation {
        case .extractText: .extract
        case .translate: .translate
        }
    }

    private static func milliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }
}
