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

    @Test("another target language is a new record on the same screenshot, and a rerun stays on it")
    func changedLanguageAddsRecord() async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let history = RunnerHistoryProbe()
        let provider = RunnerProviderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: history,
            provider: provider
        )
        let png = Data([0x89, 0x50])
        let selection = ProviderSelection(providerID: "gemini", modelID: "vision")
        for language in ["zh-Hans", "ja", "ja"] {
            _ = try await collect(
                await runner.run(
                    originalPNG: png,
                    operation: .translate(targetLanguage: language),
                    selection: selection
                )
            )
        }

        #expect(await history.operations == [
            .translate(targetLanguage: "zh-Hans"),
            .translate(targetLanguage: "ja"),
        ])
        #expect(await history.currentOutcomes.count == 2)
        #expect(await screenshotStore.saveCount == 1)
        #expect(await provider.streamCount == 3)
    }

    @Test("going back to an earlier language adds a record instead of reusing the old one")
    func returningToLanguageAddsRecord() async throws {
        let history = RunnerHistoryProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: RunnerProviderProbe()
        )
        let selection = ProviderSelection(providerID: "gemini", modelID: "vision")
        for language in ["en", "ja", "en"] {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .translate(targetLanguage: language),
                    selection: selection
                )
            )
        }

        #expect(await history.operations.count == 3)
        #expect(await history.currentOutcomes.count == 3)
    }

    @Test("a runner opened on a record never starts another one, whatever language a run asks for")
    func restoredRecordStaysBound() async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let history = RunnerHistoryProbe()
        let png = Data([7])
        let screenshot = try await screenshotStore.save(originalPNG: png)
        let selection = ProviderSelection(providerID: "gemini", modelID: "vision")
        let prepared = try await history.prepareOperation(
            screenshot: screenshot,
            selection: selection,
            operation: .translate(targetLanguage: "zh-Hans")
        )
        let stored = try #require(try await history.operation(id: prepared.operationID))
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: history,
            provider: RunnerProviderProbe(),
            restoring: stored
        )

        _ = try await collect(
            await runner.run(
                originalPNG: png,
                operation: .translate(targetLanguage: "en"),
                selection: selection
            )
        )

        #expect(await history.operations == [.translate(targetLanguage: "zh-Hans")])
        #expect(await history.currentOutcomes.keys.first == prepared.operationID)
        #expect(await history.currentOutcomes.count == 1)
    }

    @Test("a screenshot that cannot be saved reports its own reason and prepares no record")
    func screenshotSaveFailureReportsItsReason() async throws {
        let history = RunnerHistoryProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerFailingScreenshotStoreProbe(),
            historyStore: history,
            provider: RunnerOpenProviderProbe()
        )
        let events = await runner.run(
            originalPNG: Data([1]),
            operation: .extractText,
            selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "screenshot_save_failed")) {
            for try await _ in events {}
        }

        #expect(await history.operations.isEmpty)
        #expect(await history.completions.isEmpty)
        #expect(await history.outcomes.isEmpty)
    }

    @Test("canceling a running request records it as canceled, not as an incomplete response")
    func cancelingRunningRequestRecordsCanceled() async throws {
        let history = RunnerHistoryProbe()
        let provider = RunnerOpenProviderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: provider
        )
        let events = await runner.run(
            originalPNG: Data([1]),
            operation: .extractText,
            selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
        )
        let consumer = Task {
            for try await _ in events {}
        }
        for _ in 0..<500 where await provider.streamCount == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(await provider.streamCount == 1)

        consumer.cancel()
        _ = try? await consumer.value
        await runner.waitForRunToFinish()

        #expect(await history.completions == [.canceled])
        #expect(await history.outcomes.isEmpty, "no failure is recorded")
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

    @Test("a persisted operation reaches the provider with its image, record and selection")
    func persistedOperationReachesProvider() async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let provider = RunnerProviderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: RunnerHistoryProbe(),
            provider: provider
        )
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let selection = ProviderSelection(providerID: "gemini", modelID: "vision")

        _ = try await collect(await runner.run(originalPNG: png, operation: .extractText, selection: selection))

        #expect(await provider.originalPNGs == [png])
        let prepared = try #require(await provider.preparedOperations.first)
        #expect(prepared.selection == selection)
        #expect(prepared.operation == .extractText)
        #expect(prepared.screenshot == ManagedScreenshot(path: "/Pictures/shared.png", sha256: "sha"))
    }

    @Test("a model that rejects images is recorded, and the failure still reaches the caller")
    func rejectedImageIsRecorded() async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(error: ProviderAdapterError.imageInputUnsupported),
            visionCompatibility: recorder
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "image_input_unsupported")) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
                )
            )
        }

        #expect(await recorder.calls == [.failure(.deepSeek, "vision", .imageInputUnsupported)])
    }

    @Test(
        "another failure says nothing about the model's image input",
        arguments: [
            ProviderAdapterError.invalidRequest,
            ProviderAdapterError.imageTooLarge,
            ProviderAdapterError.modelUnavailable,
        ]
    )
    func otherFailureIsNotRecorded(error: ProviderAdapterError) async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(error: error),
            visionCompatibility: recorder
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: error.normalizedCode)) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
                )
            )
        }

        #expect(await recorder.calls.isEmpty)
    }

    @Test("a successful result records the model as verified, once")
    func successIsRecorded() async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(),
            visionCompatibility: recorder
        )

        _ = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: ProviderSelection(providerID: "gemini", modelID: "vision")
            )
        )

        #expect(await recorder.calls == [.success(.gemini, "vision")])
    }

    @Test("a stream that completes without text does not verify the model")
    func emptyCompletionIsNotRecorded() async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(events: [
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil)),
                .completed,
            ]),
            visionCompatibility: recorder
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "incomplete_response")) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(providerID: "gemini", modelID: "vision")
                )
            )
        }

        #expect(await recorder.calls.isEmpty)
    }

    @Test("failing to record changes neither a failure nor a success")
    func recorderFailureChangesNoOutcome() async throws {
        let recorder = RunnerVisionRecorderProbe(fails: true)
        let selection = ProviderSelection(providerID: "gemini", modelID: "vision")
        let failing = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(error: ProviderAdapterError.imageInputUnsupported),
            visionCompatibility: recorder
        )
        await #expect(throws: OperationWorkspaceRunFailure(code: "image_input_unsupported")) {
            _ = try await collect(await failing.run(originalPNG: Data([1]), operation: .extractText, selection: selection))
        }

        let succeeding = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(),
            visionCompatibility: recorder
        )
        let events = try await collect(
            await succeeding.run(originalPNG: Data([1]), operation: .extractText, selection: selection)
        )

        #expect(events.contains { if case .succeeded = $0 { true } else { false } })
        #expect(await recorder.calls == [
            .failure(.gemini, "vision", .imageInputUnsupported),
            .success(.gemini, "vision"),
        ])
    }

    @Test("a prepared record with another selection never reaches the provider and is rolled back")
    func mismatchedSelectionNeverReachesProvider() async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let provider = RunnerProviderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: RunnerHistoryProbe(returnsSelectionMismatch: true),
            provider: provider
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "history_inconsistent")) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(providerID: "openai", modelID: "vision")
                )
            )
        }

        #expect(await provider.streamCount == 0)
        #expect(await screenshotStore.discardCount == 1)
    }

    @Test("mismatched prepared operation never reaches the provider")
    func mismatchedPreparationNeverReachesProvider() async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let provider = RunnerProviderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
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
        #expect(await screenshotStore.discardCount == 1)
    }
}

private actor RunnerVisionRecorderProbe: VisionCompatibilityRecording {
    enum Call: Equatable {
        case success(ProviderID, String)
        case failure(ProviderID, String, VisionFailureEvidence)
    }

    private(set) var calls: [Call] = []
    private let fails: Bool

    init(fails: Bool = false) {
        self.fails = fails
    }

    func recordVisionSuccess(provider: ProviderID, modelID: String) async throws {
        calls.append(.success(provider, modelID))
        if fails { throw ProviderConfigurationError.modelNotFound }
    }

    func recordVisionFailure(
        provider: ProviderID,
        modelID: String,
        evidence: VisionFailureEvidence
    ) async throws {
        calls.append(.failure(provider, modelID, evidence))
        if fails { throw ProviderConfigurationError.modelNotFound }
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
    private let returnsSelectionMismatch: Bool

    init(
        failsPreparation: Bool = false,
        cancelsPreparation: Bool = false,
        failsSuccessfulFinish: Bool = false,
        returnsMismatch: Bool = false,
        returnsSelectionMismatch: Bool = false
    ) {
        self.failsPreparation = failsPreparation
        self.cancelsPreparation = cancelsPreparation
        self.failsSuccessfulFinish = failsSuccessfulFinish
        self.returnsMismatch = returnsMismatch
        self.returnsSelectionMismatch = returnsSelectionMismatch
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
        if returnsSelectionMismatch {
            return PreparedOperation(
                operationID: UUID(),
                screenshot: screenshot,
                selection: ProviderSelection(providerID: selection.providerID, modelID: "another-model"),
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

private struct RunnerFailingScreenshotStoreProbe: ScreenshotPersisting, ManagedScreenshotLoading {
    func loadIfOwned(_ screenshot: ManagedScreenshot) async throws -> Data { Data() }
    func save(originalPNG: Data) async throws -> ManagedScreenshot { throw ScreenshotStoreError.unsafePath }
    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {}
}

/// A provider stream that has started and has not finished, as a request in progress is.
private actor RunnerOpenProviderProbe: PreparedOperationStreaming {
    private(set) var streamCount = 0
    private var continuations: [AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation] = []

    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        streamCount += 1
        let pair = AsyncThrowingStream<ProviderStreamEvent, Error>.makeStream()
        continuations.append(pair.continuation)
        pair.continuation.yield(.sourceDelta("Partial"))
        return pair.stream
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
    private(set) var originalPNGs: [Data] = []
    private(set) var preparedOperations: [PreparedOperation] = []
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
        originalPNGs.append(originalPNG)
        preparedOperations.append(preparedOperation)
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
