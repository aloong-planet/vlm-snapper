import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Persisted operation workspace runner")
struct PersistedOperationWorkspaceRunnerTests {
    @Test("aligned translation survives persistence and a fresh workspace restore")
    func alignedTranslationSurvivesRestore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let history = try SQLiteHistoryStore(databaseURL: url)
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(), historyStore: history,
            provider: RunnerProviderProbe(events: [
                .translationSegments([
                    TranslationSegment(id: "a", block: "p1", kind: .paragraph, source: "Hello. ", translation: "你好。"),
                    TranslationSegment(id: "b", block: "p1", kind: .paragraph, source: "Help?", translation: "需要帮助？"),
                ]),
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil)), .completed,
            ])
        )
        _ = try await collect(await runner.run(originalPNG: Data([1]),
            operation: .translate(targetLanguage: "zh-Hans"),
            selection: ProviderSelection(providerID: "gemini", modelID: "vision")))
        let reopened = try SQLiteHistoryStore(databaseURL: url)
        let rows = try await reopened.history(matching: HistoryQuery())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        let restored = OperationWorkspaceSnapshot(restoring: row.operation)
        #expect(restored.translate.committedResult?.sourceMarkdown == "Hello. Help?")
        #expect(restored.translate.committedResult?.segments?.map(\.id) == ["a", "b"])
        #expect(restored.translate.committedResult?.segments?.last?.translation == "需要帮助？")
    }

    @Test("terminal history includes first text total latency and provider usage")
    func terminalHistoryIncludesMetrics() async throws {
        let history = RunnerHistoryProbe()
        let clock = RunnerClock(values: [
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 10.25),
            Date(timeIntervalSince1970: 10.9),
        ])
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: RunnerProviderProbe(events: [
                .sourceDelta("Text"),
                .metadata(ProviderResponseMetadata(
                    requestID: "request",
                    usage: ProviderTokenUsage(inputTokens: 10, outputTokens: 4, totalTokens: 14)
                )),
                .completed,
            ]),
            now: { clock.next() }
        )

        _ = try await collect(
            await runner.run(
                originalPNG: Data("png".utf8),
                operation: .extractText,
                selection: ProviderSelection(providerID: "openai", modelID: "vision")
            )
        )

        #expect(await history.metrics == [PersistedOperationMetrics(
            firstTextLatencyMilliseconds: 250,
            totalLatencyMilliseconds: 900,
            usage: ProviderTokenUsage(inputTokens: 10, outputTokens: 4, totalTokens: 14)
        )])
    }

    @Test("two operations reuse one screenshot and each start one typed provider stream")
    func twoOperationsReuseScreenshot() async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let history = RunnerHistoryProbe()
        let provider = RunnerProviderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: history,
            provider: provider
        )
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let selection = ProviderSelection(providerID: "gemini", modelID: "vision")

        _ = try await collect(
            await runner.run(
                originalPNG: png,
                operation: .extractText,
                selection: selection
            )
        )
        _ = try await collect(
            await runner.run(
                originalPNG: png,
                operation: .translate(targetLanguage: "en"),
                selection: selection
            )
        )

        #expect(await screenshotStore.saveCount == 1)
        #expect(await history.operations == [
            .extractText,
            .translate(targetLanguage: "en"),
        ])
        #expect(await provider.streamCount == 2)
    }

    @Test("rerunning one operation replaces its existing history record")
    func rerunReplacesExistingHistoryRecord() async throws {
        let history = RunnerHistoryProbe()
        let provider = RunnerQueuedProviderProbe(outputs: ["First result", "Replacement result"])
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: provider
        )
        let selection = ProviderSelection(providerID: "deepseek", modelID: "vision")

        _ = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: selection
            )
        )
        _ = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: selection
            )
        )

        #expect(await history.operations == [.extractText])
        #expect(await history.currentOutcomes.count == 1)
        #expect(
            await history.currentOutcomes.values.first
                == .succeeded(
                    sourceMarkdown: "Replacement result",
                    translationMarkdown: nil
                )
        )
    }

    @Test("a failed rerun preserves the previous persisted result")
    func failedRerunPreservesPreviousPersistedResult() async throws {
        let history = RunnerHistoryProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: RunnerRerunFailureProviderProbe()
        )
        let selection = ProviderSelection(providerID: "deepseek", modelID: "vision")
        _ = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: selection
            )
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "provider_unavailable")) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: selection
                )
            )
        }

        #expect(await history.operations == [.extractText])
        #expect(
            await history.currentOutcomes.values.first
                == .succeeded(sourceMarkdown: "Original result", translationMarkdown: nil)
        )
    }

    @Test("retrying a failed replacement save reuses its history identity")
    func retryingReplacementSaveReusesHistoryIdentity() async throws {
        let history = RunnerHistoryProbe()
        let provider = RunnerQueuedProviderProbe(outputs: ["Original result", "Replacement result"])
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: provider
        )
        let selection = ProviderSelection(providerID: "deepseek", modelID: "vision")
        _ = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: selection
            )
        )
        await history.setFailsSuccessfulFinish(true)

        let rerunEvents = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: selection
            )
        )
        guard case let .resultPersistenceFailed(unsaved, _) = rerunEvents.last else {
            Issue.record("Expected the replacement result to remain unsaved")
            return
        }
        await history.setFailsSuccessfulFinish(false)

        let saved = try await runner.retrySavingResult()

        #expect(saved == unsaved)
        #expect(await history.operations == [.extractText])
        #expect(await history.currentOutcomes.count == 1)
        #expect(
            await history.currentOutcomes.values.first
                == .succeeded(sourceMarkdown: "Replacement result", translationMarkdown: nil)
        )
    }

    @Test("a stream without completion persists failure instead of remaining in flight")
    func incompleteStreamPersistsFailure() async throws {
        let history = RunnerHistoryProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: RunnerProviderProbe(events: [.sourceDelta("Partial")])
        )

        await #expect(
            throws: OperationWorkspaceRunFailure(code: "incomplete_response")
        ) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(
                        providerID: "openai",
                        modelID: "vision"
                    )
                )
            )
        }

        #expect(await history.outcomes == [
            .failed(normalizedErrorCode: "incomplete_response"),
        ])
    }

    @Test("a provider cancellation persists canceled instead of failed")
    func providerCancellationPersistsCanceled() async throws {
        let history = RunnerHistoryProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: RunnerProviderProbe(error: ProviderAdapterError.cancelled)
        )

        await #expect(throws: CancellationError.self) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(
                        providerID: "openai",
                        modelID: "vision"
                    )
                )
            )
        }

        #expect(await history.completions == [.canceled])
        #expect(await history.outcomes.isEmpty)
    }

    @Test("a first history preparation failure rolls back and forgets the screenshot")
    func preparationFailureRollsBackScreenshot() async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let history = RunnerHistoryProbe(failsPreparation: true)
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: history,
            provider: RunnerProviderProbe()
        )
        let selection = ProviderSelection(providerID: "openai", modelID: "vision")

        await #expect(
            throws: OperationWorkspaceRunFailure(code: "operation_failed")
        ) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: selection
                )
            )
        }
        #expect(await screenshotStore.discardCount == 1)

        await history.setFailsPreparation(false)
        _ = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: selection
            )
        )
        #expect(await screenshotStore.saveCount == 2)
    }

    @Test("a canceled first history preparation rolls back and forgets the screenshot")
    func canceledPreparationRollsBackScreenshot() async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let history = RunnerHistoryProbe(cancelsPreparation: true)
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: history,
            provider: RunnerProviderProbe()
        )
        let selection = ProviderSelection(providerID: "openai", modelID: "vision")

        await #expect(throws: CancellationError.self) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: selection
                )
            )
        }
        #expect(await screenshotStore.discardCount == 1)

        await history.setCancelsPreparation(false)
        _ = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: selection
            )
        )
        #expect(await screenshotStore.saveCount == 2)
    }

    @Test("retrying final persistence does not start another provider stream")
    func retryFinalPersistenceDoesNotCallProvider() async throws {
        let history = RunnerHistoryProbe(failsSuccessfulFinish: true)
        let provider = RunnerProviderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: provider
        )

        let events = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: ProviderSelection(
                    providerID: "openai",
                    modelID: "vision"
                )
            )
        )
        guard case let .resultPersistenceFailed(unsaved, _) = events.last else {
            Issue.record("Expected an unsaved completed result")
            return
        }

        await history.setFailsSuccessfulFinish(false)
        let saved = try await runner.retrySavingResult()

        #expect(saved == unsaved)
        #expect(await provider.streamCount == 1)
    }

    @Test("mismatched prepared operation never reaches the provider")
    func mismatchedPreparationNeverReachesProvider() async throws {
        let provider = RunnerProviderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(returnsMismatch: true),
            provider: provider
        )

        await #expect(
            throws: OperationWorkspaceRunFailure(code: "history_inconsistent")
        ) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(
                        providerID: "openai",
                        modelID: "vision"
                    )
                )
            )
        }
        #expect(await provider.streamCount == 0)
    }
}

private func collect(
    _ stream: AsyncThrowingStream<OperationWorkspaceRunEvent, Error>
) async throws -> [OperationWorkspaceRunEvent] {
    var events: [OperationWorkspaceRunEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

private actor RunnerScreenshotStoreProbe: ScreenshotPersisting, ManagedScreenshotLoading {
    private(set) var saveCount = 0
    private(set) var discardCount = 0
    private var png = Data()

    func loadIfOwned(_ screenshot: ManagedScreenshot) async throws -> Data { png }

    func save(originalPNG: Data) async throws -> ManagedScreenshot {
        saveCount += 1
        png = originalPNG
        return ManagedScreenshot(path: "/Pictures/shared.png", sha256: "sha")
    }

    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {
        discardCount += 1
    }
}

private actor RunnerHistoryProbe: OperationHistoryWriting {
    private var stored: [UUID: StoredOperation] = [:]

    func operation(id: UUID) async throws -> StoredOperation? { stored[id] }
    private(set) var operations: [ProviderOperation] = []
    private(set) var outcomes: [PersistedOperationOutcome] = []
    private(set) var completions: [OperationCompletion] = []
    private(set) var metrics: [PersistedOperationMetrics] = []
    private(set) var currentOutcomes: [UUID: PersistedOperationOutcome] = [:]
    private var failsPreparation: Bool
    private var cancelsPreparation: Bool
    private var failsSuccessfulFinish: Bool
    private let returnsMismatch: Bool

    init(
        failsPreparation: Bool = false,
        cancelsPreparation: Bool = false,
        failsSuccessfulFinish: Bool = false,
        returnsMismatch: Bool = false
    ) {
        self.failsPreparation = failsPreparation
        self.cancelsPreparation = cancelsPreparation
        self.failsSuccessfulFinish = failsSuccessfulFinish
        self.returnsMismatch = returnsMismatch
    }

    func setFailsPreparation(_ value: Bool) {
        failsPreparation = value
    }

    func setFailsSuccessfulFinish(_ value: Bool) {
        failsSuccessfulFinish = value
    }

    func setCancelsPreparation(_ value: Bool) {
        cancelsPreparation = value
    }

    func prepareOperation(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection,
        operation: ProviderOperation
    ) async throws -> PreparedOperation {
        if cancelsPreparation {
            throw CancellationError()
        }
        if failsPreparation {
            throw RunnerProbeError.failed
        }
        operations.append(operation)
        if returnsMismatch {
            return PreparedOperation(
                operationID: UUID(),
                screenshot: ManagedScreenshot(path: "/wrong.png", sha256: "wrong"),
                selection: selection,
                operation: operation
            )
        }
        let id = UUID()
        let targetLanguage: String?
        switch operation {
        case .extractText: targetLanguage = nil
        case let .translate(language): targetLanguage = language
        }
        stored[id] = StoredOperation(id: id, screenshot: screenshot, selection: selection,
            status: .succeeded, kind: targetLanguage == nil ? .extract : .translate,
            targetLanguage: targetLanguage)
        return PreparedOperation(
            operationID: id,
            screenshot: screenshot,
            selection: selection,
            operation: operation
        )
    }

    func markInFlight(
        operationID: UUID,
        as progress: OperationProgress
    ) async throws {}

    func finish(
        operationID: UUID,
        with outcome: PersistedOperationOutcome
    ) async throws {
        if failsSuccessfulFinish, case .succeeded = outcome {
            throw RunnerProbeError.failed
        }
        outcomes.append(outcome)
        currentOutcomes[operationID] = outcome
    }

    func finish(
        operationID: UUID,
        with outcome: PersistedOperationOutcome,
        metrics: PersistedOperationMetrics
    ) async throws {
        try await finish(operationID: operationID, with: outcome)
        self.metrics.append(metrics)
    }

    func replace(
        operationID: UUID,
        selection: ProviderSelection,
        operation: ProviderOperation,
        with outcome: PersistedOperationOutcome,
        metrics: PersistedOperationMetrics
    ) async throws {
        try await finish(
            operationID: operationID,
            with: outcome,
            metrics: metrics
        )
    }

    func finish(
        operationID: UUID,
        as completion: OperationCompletion
    ) async throws {
        completions.append(completion)
    }
}

private actor RunnerQueuedProviderProbe: PreparedOperationStreaming {
    private var outputs: [String]

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let output = outputs.removeFirst()
        return AsyncThrowingStream { continuation in
            continuation.yield(.sourceDelta(output))
            continuation.yield(
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil))
            )
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

private actor RunnerRerunFailureProviderProbe: PreparedOperationStreaming {
    private var streamCount = 0

    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        streamCount += 1
        if streamCount == 2 {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ProviderAdapterError.providerUnavailable)
            }
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.sourceDelta("Original result"))
            continuation.yield(
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil))
            )
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

private final class RunnerClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]

    init(values: [Date]) { self.values = values }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

private enum RunnerProbeError: Error {
    case failed
}

private actor RunnerProviderProbe: PreparedOperationStreaming {
    private(set) var streamCount = 0
    private let events: [ProviderStreamEvent]?
    private let error: (any Error)?

    init(
        events: [ProviderStreamEvent]? = nil,
        error: (any Error)? = nil
    ) {
        self.events = events
        self.error = error
    }

    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        streamCount += 1
        let operation = preparedOperation.operation
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            if let events {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
                return
            }
            continuation.yield(.sourceDelta("Source"))
            if case .translate = operation {
                continuation.yield(.translationDelta("Translation"))
            }
            continuation.yield(
                .metadata(
                    ProviderResponseMetadata(requestID: nil, usage: nil)
                )
            )
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}
